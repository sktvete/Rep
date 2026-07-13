#!/usr/bin/env python3
"""Split exercise GIFs into frames, upscale, swap white for green, re-encode."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image, ImageSequence
except ImportError:
    print("Missing dependency: pip install Pillow", file=sys.stderr)
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parent
DEFAULT_MANIFEST = ROOT / "exercise-media" / "manifest.json"
DEFAULT_MEDIA_ROOT = ROOT / "exercise-media"
GREEN = (0, 255, 0)


def load_manifest(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise ValueError("Manifest must be a JSON array.")
    return data


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["curl", "-fsSL", url, "-o", str(destination)],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0 and destination.exists() and destination.stat().st_size > 0:
        return

    request = urllib.request.Request(url, headers={"User-Agent": "RepExerciseMediaScript/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        destination.write_bytes(response.read())


def is_near_white(rgb: tuple[int, int, int], threshold: int) -> bool:
    r, g, b = rgb
    return r >= threshold and g >= threshold and b >= threshold


def replace_white_with_green(image: Image.Image, threshold: int) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0 or is_near_white((r, g, b), threshold):
                pixels[x, y] = (*GREEN, 255)
    return rgba.convert("RGB")


def upscale(image: Image.Image, target_size: int) -> Image.Image:
    width, height = image.size
    scale = target_size / max(width, height)
    if scale <= 1:
        return image.copy()
    new_size = (max(1, round(width * scale)), max(1, round(height * scale)))
    return image.resize(new_size, Image.Resampling.LANCZOS)


def extract_frames(source: Path) -> tuple[list[Image.Image], list[int]]:
    with Image.open(source) as image:
        frames = [frame.copy().convert("RGB") for frame in ImageSequence.Iterator(image)]
        if not frames:
            raise ValueError(f"No frames found in {source}")
        duration = image.info.get("duration", 100)
        durations = [duration] * len(frames)
    return frames, durations


def save_frames(frames: Iterable[Image.Image], directory: Path, prefix: str) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames):
        frame.save(directory / f"{prefix}{index:03d}.png")


def quantize_frames(frames: list[Image.Image]) -> list[Image.Image]:
    if len(frames) == 1:
        return [frames[0].quantize(colors=256, method=Image.Quantize.MEDIANCUT)]

    width, height = frames[0].size
    sheet = Image.new("RGB", (width, height * len(frames)))
    for index, frame in enumerate(frames):
        sheet.paste(frame, (0, index * height))

    palette_image = sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    return [
        frame.quantize(palette=palette_image, dither=Image.Dither.FLOYDSTEINBERG)
        for frame in frames
    ]


def save_gif(frames: list[Image.Image], durations: list[int], destination: Path) -> None:
    quantized = quantize_frames(frames)
    destination.parent.mkdir(parents=True, exist_ok=True)
    quantized[0].save(
        destination,
        save_all=True,
        append_images=quantized[1:],
        duration=durations,
        loop=0,
        disposal=2,
        optimize=True,
    )


def save_webp(frames: list[Image.Image], durations: list[int], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        destination,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        lossless=False,
        quality=82,
        method=6,
    )


def human_bytes(size: int) -> str:
    if size < 1024:
        return f"{size} B"
    units = ["KB", "MB", "GB"]
    value = float(size)
    for unit in units:
        value /= 1024
        if value < 1024:
            return f"{value:.1f} {unit}"
    return f"{value:.1f} TB"


def process_exercise(
    entry: dict,
    media_root: Path,
    target_size: int,
    white_threshold: int,
    force_download: bool,
) -> None:
    slug = entry["slug"]
    gif_url = entry["gifUrl"]
    backup_dir = media_root / "backups" / slug
    working_dir = media_root / "working" / slug
    output_dir = media_root / "output"
    original_path = backup_dir / "original.gif"

    backup_dir.mkdir(parents=True, exist_ok=True)
    if force_download or not original_path.exists():
        print(f"→ Downloading {entry['name']}…")
        download(gif_url, original_path)
    elif original_path.stat().st_size == 0:
        download(gif_url, original_path)

    shutil.copy2(original_path, backup_dir / "original-copy.gif")

    frames, durations = extract_frames(original_path)
    save_frames(frames, working_dir / "01-original-frames", "frame-")

    upscaled = [upscale(frame, target_size) for frame in frames]
    save_frames(upscaled, working_dir / "02-upscaled-frames", "frame-")

    green_frames = [replace_white_with_green(frame, white_threshold) for frame in upscaled]
    save_frames(green_frames, working_dir / "03-green-frames", "frame-")

    gif_out = output_dir / f"{slug}.gif"
    webp_out = output_dir / f"{slug}.webp"
    save_gif(green_frames, durations, gif_out)
    save_webp(green_frames, durations, webp_out)

    print(
        f"✓ {entry['name']}: {len(frames)} frames @ {upscaled[0].size[0]}x{upscaled[0].size[1]} | "
        f"original {human_bytes(original_path.stat().st_size)} | "
        f"gif {human_bytes(gif_out.stat().st_size)} | "
        f"webp {human_bytes(webp_out.stat().st_size)}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--media-root", type=Path, default=DEFAULT_MEDIA_ROOT)
    parser.add_argument("--target-size", type=int, default=720, help="Longest edge in pixels.")
    parser.add_argument(
        "--white-threshold",
        type=int,
        default=235,
        help="Pixels with R,G,B all >= this value become green.",
    )
    parser.add_argument("--slug", action="append", help="Process only these manifest slugs.")
    parser.add_argument("--download", action="store_true", help="Re-download originals from CDN.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = load_manifest(args.manifest)
    if args.slug:
        wanted = set(args.slug)
        manifest = [entry for entry in manifest if entry["slug"] in wanted]
        missing = wanted - {entry["slug"] for entry in manifest}
        if missing:
            raise SystemExit(f"Unknown slug(s): {', '.join(sorted(missing))}")

    if not manifest:
        raise SystemExit("No exercises selected.")

    args.media_root.mkdir(parents=True, exist_ok=True)
    print(f"Media root: {args.media_root}")
    for entry in manifest:
        process_exercise(
            entry,
            media_root=args.media_root,
            target_size=args.target_size,
            white_threshold=args.white_threshold,
            force_download=args.download,
        )


if __name__ == "__main__":
    main()
