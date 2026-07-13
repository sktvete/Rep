#!/usr/bin/env python3
"""Benchmark exercise GIF processing: split, upscale, white-key, encode."""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Optional

try:
    from PIL import Image, ImageSequence
except ImportError:
    print("Missing dependency: pip install Pillow", file=sys.stderr)
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parent
DEFAULT_MANIFEST = ROOT / "exercise-media" / "manifest.json"
DEFAULT_MEDIA_ROOT = ROOT / "exercise-media" / "benchmark"


@dataclass
class PhaseTimes:
    download_s: float = 0.0
    extract_s: float = 0.0
    upscale_s: float = 0.0
    matte_s: float = 0.0
    encode_s: float = 0.0

    @property
    def total_s(self) -> float:
        return self.download_s + self.extract_s + self.upscale_s + self.matte_s + self.encode_s


@dataclass
class AccuracyMetrics:
    transparent_pct: float
    subject_white_pct: float
    halo_edge_pct: float
    opaque_pixels: int
    transparent_pixels: int


@dataclass
class ExerciseResult:
    slug: str
    name: str
    frame_count: int
    source_size: tuple[int, int]
    output_size: tuple[int, int]
    upscale_method: str
    times: PhaseTimes
    accuracy: AccuracyMetrics
    original_bytes: int
    webp_bytes: int
    gif_bytes: int
    paths: dict[str, str] = field(default_factory=dict)


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
    request = urllib.request.Request(url, headers={"User-Agent": "RepExerciseMediaBenchmark/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        destination.write_bytes(response.read())


def detect_upscale_method(model: str) -> str:
    if model != "pillow-lanczos" and shutil.which("realesrgan-ncnn-vulkan"):
        return "realesrgan-ncnn-vulkan"
    if model != "pillow-lanczos":
        print("Warning: realesrgan-ncnn-vulkan not found, falling back to pillow-lanczos.", file=sys.stderr)
    return "pillow-lanczos"


def is_near_white(rgb: tuple[int, int, int], threshold: int) -> bool:
    r, g, b = rgb
    return r >= threshold and g >= threshold and b >= threshold


def replace_white_with_alpha(image: Image.Image, threshold: int) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            if is_near_white((r, g, b), threshold):
                pixels[x, y] = (r, g, b, 0)
    return rgba


def upscale_pillow(image: Image.Image, target_size: int) -> Image.Image:
    width, height = image.size
    scale = target_size / max(width, height)
    if scale <= 1:
        return image.copy()
    new_size = (max(1, round(width * scale)), max(1, round(height * scale)))
    return image.resize(new_size, Image.Resampling.LANCZOS)


def upscale_realesrgan(frames_dir: Path, output_dir: Path, scale: int, model: str) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    binary = os.environ.get("REALESRGAN_BIN", "realesrgan-ncnn-vulkan")
    command = [
        binary,
        "-i",
        str(frames_dir),
        "-o",
        str(output_dir),
        "-n",
        model,
        "-s",
        str(scale),
        "-f",
        "png",
        "-g",
        os.environ.get("REALESRGAN_GPU", "0"),
    ]
    subprocess.run(command, check=True)


def load_png_frames(directory: Path) -> list[Image.Image]:
    paths = sorted(directory.glob("*.png"))
    return [Image.open(path).convert("RGBA" if "alpha" in directory.name else "RGB") for path in paths]


def extract_frames(source: Path) -> tuple[list[Image.Image], list[int]]:
    with Image.open(source) as image:
        frames = [frame.copy().convert("RGB") for frame in ImageSequence.Iterator(image)]
        if not frames:
            raise ValueError(f"No frames found in {source}")
        duration = image.info.get("duration", 100)
        durations = [duration] * len(frames)
    return frames, durations


def save_png_frames(frames: Iterable[Image.Image], directory: Path, prefix: str) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames):
        frame.save(directory / f"{prefix}{index:03d}.png")


def quantize_frames(frames: list[Image.Image]) -> list[Image.Image]:
    rgb_frames = [frame.convert("RGB") for frame in frames]
    if len(rgb_frames) == 1:
        return [rgb_frames[0].quantize(colors=256, method=Image.Quantize.MEDIANCUT)]

    width, height = rgb_frames[0].size
    sheet = Image.new("RGB", (width, height * len(rgb_frames)))
    for index, frame in enumerate(rgb_frames):
        sheet.paste(frame, (0, index * height))

    palette_image = sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    return [
        frame.quantize(palette=palette_image, dither=Image.Dither.FLOYDSTEINBERG)
        for frame in rgb_frames
    ]


def save_gif(frames: list[Image.Image], durations: list[int], destination: Path) -> None:
    rgb_frames = [frame.convert("RGB") for frame in frames]
    quantized = quantize_frames(rgb_frames)
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


def measure_accuracy(frames: list[Image.Image], white_threshold: int) -> AccuracyMetrics:
    transparent_pixels = 0
    opaque_pixels = 0
    subject_white_pixels = 0
    halo_edge_pixels = 0

    for frame in frames:
        rgba = frame.convert("RGBA")
        pixels = rgba.load()
        width, height = rgba.size
        for y in range(height):
            for x in range(width):
                r, g, b, a = pixels[x, y]
                if a < 16:
                    transparent_pixels += 1
                    continue
                opaque_pixels += 1
                if is_near_white((r, g, b), white_threshold):
                    subject_white_pixels += 1
                    neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    for nx, ny in neighbors:
                        if nx < 0 or ny < 0 or nx >= width or ny >= height:
                            continue
                        if pixels[nx, ny][3] < 16:
                            halo_edge_pixels += 1
                            break

    total = transparent_pixels + opaque_pixels
    transparent_pct = (transparent_pixels / total * 100) if total else 0.0
    subject_white_pct = (subject_white_pixels / opaque_pixels * 100) if opaque_pixels else 0.0
    halo_edge_pct = (halo_edge_pixels / opaque_pixels * 100) if opaque_pixels else 0.0
    return AccuracyMetrics(
        transparent_pct=round(transparent_pct, 2),
        subject_white_pct=round(subject_white_pct, 2),
        halo_edge_pct=round(halo_edge_pct, 2),
        opaque_pixels=opaque_pixels,
        transparent_pixels=transparent_pixels,
    )


def save_dark_preview(alpha_frame: Image.Image, destination: Path, background: tuple[int, int, int] = (18, 18, 20)) -> None:
    canvas = Image.new("RGBA", alpha_frame.size, (*background, 255))
    canvas.alpha_composite(alpha_frame.convert("RGBA"))
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(destination, quality=95)


def human_bytes(size: int) -> str:
    if size < 1024:
        return f"{size} B"
    value = float(size)
    for unit in ["KB", "MB", "GB"]:
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
    upscale_method: str,
    realesrgan_model: str,
) -> ExerciseResult:
    slug = entry["slug"]
    gif_url = entry["gifUrl"]
    backup_dir = media_root / "backups" / slug
    working_dir = media_root / "working" / slug
    output_dir = media_root / "output"
    original_path = backup_dir / "original.gif"
    times = PhaseTimes()

    backup_dir.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()
    if force_download or not original_path.exists() or original_path.stat().st_size == 0:
        download(gif_url, original_path)
    times.download_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    frames, durations = extract_frames(original_path)
    source_size = frames[0].size
    save_png_frames(frames, working_dir / "01-original-frames", "frame-")
    times.extract_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    if upscale_method == "realesrgan-ncnn-vulkan":
        raw_dir = working_dir / "01-original-frames"
        upscaled_dir = working_dir / "02-upscaled-frames"
        scale = max(2, min(4, round(target_size / max(source_size))))
        upscale_realesrgan(raw_dir, upscaled_dir, scale, realesrgan_model)
        upscaled = [Image.open(path).convert("RGB") for path in sorted(upscaled_dir.glob("*.png"))]
    else:
        upscaled = [upscale_pillow(frame, target_size) for frame in frames]
        save_png_frames(upscaled, working_dir / "02-upscaled-frames", "frame-")
    times.upscale_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    alpha_frames = [replace_white_with_alpha(frame, white_threshold) for frame in upscaled]
    save_png_frames(alpha_frames, working_dir / "03-alpha-frames", "frame-")
    times.matte_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    webp_out = output_dir / f"{slug}.webp"
    gif_out = output_dir / f"{slug}.gif"
    preview_out = output_dir / f"{slug}-preview.png"
    dark_preview_out = output_dir / f"{slug}-on-dark.png"
    save_webp(alpha_frames, durations, webp_out)
    save_gif(alpha_frames, durations, gif_out)
    mid = alpha_frames[len(alpha_frames) // 2]
    mid.save(preview_out)
    save_dark_preview(mid, dark_preview_out)
    times.encode_s = time.perf_counter() - t0

    accuracy = measure_accuracy(alpha_frames, white_threshold)
    return ExerciseResult(
        slug=slug,
        name=entry["name"],
        frame_count=len(frames),
        source_size=source_size,
        output_size=alpha_frames[0].size,
        upscale_method=upscale_method,
        times=times,
        accuracy=accuracy,
        original_bytes=original_path.stat().st_size,
        webp_bytes=webp_out.stat().st_size,
        gif_bytes=gif_out.stat().st_size,
        paths={
            "original": str(original_path),
            "preview": str(preview_out),
            "dark_preview": str(dark_preview_out),
            "webp": str(webp_out),
            "gif": str(gif_out),
            "alpha_frames": str(working_dir / "03-alpha-frames"),
        },
    )


def print_result(result: ExerciseResult) -> None:
    print(f"\n{result.name} ({result.slug})")
    print(
        f"  {result.frame_count} frames  {result.source_size[0]}x{result.source_size[1]}"
        f" → {result.output_size[0]}x{result.output_size[1]}  [{result.upscale_method}]"
    )
    print(
        f"  time  down {result.times.download_s:.2f}s  extract {result.times.extract_s:.2f}s"
        f"  upscale {result.times.upscale_s:.2f}s  matte {result.times.matte_s:.2f}s"
        f"  encode {result.times.encode_s:.2f}s  total {result.times.total_s:.2f}s"
    )
    print(
        f"  accuracy  transparent {result.accuracy.transparent_pct:.1f}%"
        f"  subject-white {result.accuracy.subject_white_pct:.2f}%"
        f"  halo-edges {result.accuracy.halo_edge_pct:.2f}%"
    )
    print(
        f"  size  original {human_bytes(result.original_bytes)}"
        f"  webp {human_bytes(result.webp_bytes)}"
        f"  gif {human_bytes(result.gif_bytes)}"
    )
    print(f"  preview  {result.paths['preview']}")
    print(f"  on dark  {result.paths['dark_preview']}")


def write_report(
    results: list[ExerciseResult],
    media_root: Path,
    target_size: int,
    white_threshold: int,
) -> Path:
    total_frames = sum(result.frame_count for result in results)
    total_seconds = sum(result.times.total_s for result in results)
    report = {
        "host": platform.platform(),
        "upscale_method": results[0].upscale_method if results else "unknown",
        "target_size": target_size,
        "white_threshold": white_threshold,
        "exercise_count": len(results),
        "frame_count": total_frames,
        "total_seconds": round(total_seconds, 2),
        "seconds_per_frame": round(total_seconds / total_frames, 3) if total_frames else 0,
        "projected_catalog_seconds": round((total_seconds / total_frames) * 61200, 0) if total_frames else 0,
        "projected_app_subset_seconds": round((total_seconds / total_frames) * 18800, 0) if total_frames else 0,
        "results": [
            {
                "slug": result.slug,
                "name": result.name,
                "frame_count": result.frame_count,
                "source_size": result.source_size,
                "output_size": result.output_size,
                "times": result.times.__dict__,
                "accuracy": result.accuracy.__dict__,
                "bytes": {
                    "original": result.original_bytes,
                    "webp": result.webp_bytes,
                    "gif": result.gif_bytes,
                },
                "paths": result.paths,
            }
            for result in results
        ],
    }
    report_path = media_root / "benchmark-report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--media-root", type=Path, default=DEFAULT_MEDIA_ROOT)
    parser.add_argument("--target-size", type=int, default=720)
    parser.add_argument("--white-threshold", type=int, default=235)
    parser.add_argument("--slug", action="append")
    parser.add_argument("--download", action="store_true")
    parser.add_argument(
        "--upscale",
        choices=["auto", "pillow-lanczos", "realesrgan-ncnn-vulkan"],
        default="auto",
        help="Upscale backend (auto prefers Real-ESRGAN when installed).",
    )
    parser.add_argument(
        "--realesrgan-model",
        default=os.environ.get("REALESRGAN_MODEL", "4x-UltraSharp-fp16"),
        help="Model name for realesrgan-ncnn-vulkan -n (e.g. 4x-UltraSharp-fp16, realesrgan-x4plus).",
    )
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

    if args.upscale == "auto":
        upscale_method = detect_upscale_method("realesrgan-ncnn-vulkan")
    else:
        upscale_method = detect_upscale_method(args.upscale)
    args.media_root.mkdir(parents=True, exist_ok=True)
    print(f"Host: {platform.machine()} / {platform.system()}")
    print(f"Upscale: {upscale_method} (model: {args.realesrgan_model})")
    print(f"Output: {args.media_root}")

    results: list[ExerciseResult] = []
    for entry in manifest:
        results.append(
            process_exercise(
                entry,
                media_root=args.media_root,
                target_size=args.target_size,
                white_threshold=args.white_threshold,
                force_download=args.download,
                upscale_method=upscale_method,
                realesrgan_model=args.realesrgan_model,
            )
        )
        print_result(results[-1])

    report_path = write_report(results, args.media_root, args.target_size, args.white_threshold)
    total_frames = sum(result.frame_count for result in results)
    total_seconds = sum(result.times.total_s for result in results)
    avg_subject_white = sum(result.accuracy.subject_white_pct for result in results) / len(results)
    avg_halo = sum(result.accuracy.halo_edge_pct for result in results) / len(results)

    print("\n--- summary ---")
    print(f"exercises: {len(results)}  frames: {total_frames}  total: {total_seconds:.1f}s")
    print(f"per frame: {total_seconds / total_frames:.3f}s")
    print(f"avg subject-white: {avg_subject_white:.2f}%  avg halo-edges: {avg_halo:.2f}%")
    print(f"projected 61.2k frames: {total_seconds / total_frames * 61200 / 3600:.1f} hours")
    print(f"report: {report_path}")


if __name__ == "__main__":
    main()
