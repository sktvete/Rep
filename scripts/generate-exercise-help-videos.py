#!/usr/bin/env python3
"""Generate the bundled exercise help video catalog from prioritized YouTube search."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASCEND_CACHE = Path("/tmp/rep-ascend/all-unique.json")
BUNDLED_CATALOG = ROOT / "Rep/Resources/Catalog/rep-exercise-catalog-v1.json"
OUTPUT = ROOT / "Rep/Resources/Catalog/exercise-help-videos-v1.json"
POPULARITY_SOURCE = ROOT / "Rep/Shared/ExercisePopularity.swift"

PRIORITY_CHANNELS = [
    "Jeff Nippard",
    "Menno Henselmans",
    "Squat University",
    "Jeremy Ethier",
    "2 Minute Tutorials",
    "Colossus Fitness",
    "E3 Rehab",
    "FitnessFAQs",
    "Hybrid Calisthenics",
    "ScottHermanFitness",
    "Renaissance Periodization",
    "ATHLEAN-X",
    "MuscleWiki",
    "StrongFirst",
    "Bodybuilding.com",
    "TylerPath",
]

REJECT_TITLE_WORDS = ("stop", "waste", "wrong")
SEARCH_RESULT_COUNT = 8
PROGRESS_WIDTH = 36
YTDLP = shutil.which("yt-dlp") or str(
    Path.home() / "Library/Python/3.9/bin/yt-dlp"
)


@dataclass(frozen=True)
class ExerciseTarget:
    name: str
    equipment: str
    bundled_catalog_id: str


@dataclass(frozen=True)
class VideoCandidate:
    video_id: str
    title: str
    channel: str


def norm(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", " ", value.lower())
    return " ".join(cleaned.split())


def normalize_channel(value: str) -> str:
    cleaned = value.lower()
    cleaned = cleaned.replace("™", "").replace("®", "")
    cleaned = re.sub(r"[^a-z0-9]+", "", cleaned)
    return cleaned


def channel_priority(channel: str) -> int:
    normalized = normalize_channel(channel)
    for index, preferred in enumerate(PRIORITY_CHANNELS):
        if channel_matches(channel, preferred):
            return index
    return len(PRIORITY_CHANNELS)


def channel_matches(candidate_channel: str, preferred_channel: str) -> bool:
    normalized_candidate = normalize_channel(candidate_channel)
    normalized_preferred = normalize_channel(preferred_channel)
    if normalized_candidate == normalized_preferred:
        return True
    if normalized_preferred in normalized_candidate or normalized_candidate in normalized_preferred:
        return True
    if normalized_candidate.startswith(normalized_preferred) or normalized_preferred.startswith(
        normalized_candidate
    ):
        return True
    return False


def title_rejected(title: str) -> bool:
    lower = title.lower()
    return any(word in lower for word in REJECT_TITLE_WORDS)


def title_tokens(name: str) -> list[str]:
    stopwords = {
        "a",
        "an",
        "and",
        "for",
        "of",
        "the",
        "to",
        "with",
        "barbell",
        "dumbbell",
        "cable",
        "machine",
        "bodyweight",
        "smith",
    }
    return [
        token
        for token in norm(name).split()
        if token not in stopwords and len(token) > 2
    ]


def title_matches_exercise(title: str, exercise_name: str) -> bool:
    title_norm = norm(title)
    tokens = title_tokens(exercise_name)
    if not tokens:
        return True
    matches = sum(1 for token in tokens if token in title_norm)
    required = 1 if len(tokens) == 1 else max(1, len(tokens) // 2)
    return matches >= required


def load_popular_exercise_names() -> list[str]:
    source = POPULARITY_SOURCE.read_text()
    match = re.search(
        r"private static let orderedNames: \[String\] = \[(.*?)\]",
        source,
        re.DOTALL,
    )
    if not match:
        raise RuntimeError(f"Could not parse orderedNames from {POPULARITY_SOURCE}")
    return re.findall(r'"([^"]+)"', match.group(1))


def popularity_rank(name: str, popular_names: list[str]) -> int:
    normalized = norm(name)
    rank_by_norm = {norm(popular): index for index, popular in enumerate(popular_names)}
    return rank_by_norm.get(normalized, len(popular_names) + 1_000)


def build_targets(bundled: list[dict], limit: int | None) -> list[ExerciseTarget]:
    popular_names = load_popular_exercise_names()
    ranked: list[tuple[int, str, ExerciseTarget]] = []
    seen_ids: set[str] = set()

    for item in bundled:
        catalog_id = item["id"]
        if catalog_id in seen_ids:
            continue
        seen_ids.add(catalog_id)
        name = item["name"]
        equipment = item.get("equipment") or "other"
        target = ExerciseTarget(
            name=name,
            equipment=equipment,
            bundled_catalog_id=catalog_id,
        )
        ranked.append((popularity_rank(name, popular_names), name.lower(), target))

    ranked.sort(key=lambda row: (row[0], row[1]))
    targets = [row[2] for row in ranked]
    if limit is not None:
        targets = targets[:limit]
    return targets


def load_existing_mappings() -> tuple[list[dict], set[str], set[tuple[str, str]]]:
    if not OUTPUT.exists():
        return [], set(), set()

    payload = json.loads(OUTPUT.read_text())
    mappings = payload.get("mappings", [])
    done_ids: set[str] = set()
    done_keys: set[tuple[str, str]] = set()
    for mapping in mappings:
        done_ids.add(mapping["exerciseId"])
        bundled_id = mapping.get("bundledCatalogID")
        if isinstance(bundled_id, str) and bundled_id:
            done_ids.add(bundled_id)
        equipment = mapping.get("equipment") or "other"
        done_keys.add((norm(mapping["exerciseName"]), equipment))
    return mappings, done_ids, done_keys


class ProgressBar:
    def __init__(self, total: int, *, enabled: bool = True) -> None:
        self.total = max(total, 1)
        self.current = 0
        self.mapped = 0
        self.skipped = 0
        self.rejected = 0
        self.enabled = enabled and sys.stderr.isatty()
        self._status = ""

    def set_counts(self, mapped: int, skipped: int, rejected: int) -> None:
        self.mapped = mapped
        self.skipped = skipped
        self.rejected = rejected

    def advance(self, current: int, status: str, *, mapped: int | None = None, skipped: int | None = None, rejected: int | None = None) -> None:
        self.current = current
        self._status = status
        if mapped is not None:
            self.mapped = mapped
        if skipped is not None:
            self.skipped = skipped
        if rejected is not None:
            self.rejected = rejected
        self._render()

    def _render(self) -> None:
        ratio = min(1.0, self.current / self.total)
        filled = int(PROGRESS_WIDTH * ratio)
        bar = "█" * filled + "░" * (PROGRESS_WIDTH - filled)
        counts = f"mapped {self.mapped} · skipped {self.skipped} · rejected {self.rejected}"
        line = (
            f"{bar} {self.current}/{self.total} ({ratio * 100:5.1f}%) "
            f"{counts} · {self._status}"
        )
        if self.enabled:
            sys.stderr.write(f"\r{line[:140]}")
            sys.stderr.flush()
        elif self.current == 1 or self.current == self.total or self.current % 10 == 0:
            print(line[:140], flush=True)

    def note(self, message: str) -> None:
        if not self.enabled:
            print(message, flush=True)
            return
        sys.stderr.write("\n")
        sys.stderr.flush()
        print(message, flush=True)

    def finish(self) -> None:
        if self.enabled:
            self._render()
            sys.stderr.write("\n")
            sys.stderr.flush()


def write_catalog(
    mappings: list[dict],
    bundled_count: int,
    ascend_count: int,
    skipped: list[str],
    rejected: list[str],
    *,
    progress: ProgressBar | None = None,
) -> None:
    payload = {
        "schemaVersion": 1,
        "catalogVersion": time.strftime("%Y.%m.%d.1"),
        "publishedAt": time.strftime("%Y-%m-%dT00:00:00Z"),
        "bundledExerciseCount": bundled_count,
        "ascendApiExerciseCount": ascend_count or 1500,
        "mappings": mappings,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n")
    if progress is not None:
        progress.note(f"Wrote {len(mappings)} mappings to {OUTPUT}")
    else:
        print(f"\nWrote {len(mappings)} mappings to {OUTPUT}", flush=True)
    if skipped:
        summary = f"Skipped ({len(skipped)}): {', '.join(skipped[:20])}" + (" …" if len(skipped) > 20 else "")
        if progress is not None:
            progress.note(summary)
        else:
            print(summary, flush=True)
    if rejected:
        if progress is not None:
            progress.note("Rejected:")
        else:
            print("Rejected:", flush=True)
        for item in rejected[:20]:
            line = f"  {item}"
            if progress is not None:
                progress.note(line)
            else:
                print(line, flush=True)
        if len(rejected) > 20:
            tail = f"  … and {len(rejected) - 20} more"
            if progress is not None:
                progress.note(tail)
            else:
                print(tail, flush=True)


def verify_oembed(video_id: str) -> dict[str, str] | None:
    url = (
        "https://www.youtube.com/oembed?"
        f"url=https://www.youtube.com/watch?v={video_id}&format=json"
    )
    try:
        out = subprocess.check_output(
            ["curl", "-s", "-w", "\n%{http_code}", url],
            text=True,
            timeout=20,
        )
        body, code = out.rsplit("\n", 1)
        if code != "200":
            return None
        meta = json.loads(body)
        return {
            "title": meta["title"],
            "channel": meta["author_name"],
        }
    except Exception:
        return None


def search_youtube(query: str) -> list[VideoCandidate]:
    if not Path(YTDLP).exists():
        raise RuntimeError(
            "yt-dlp is required. Install with: python3 -m pip install yt-dlp"
        )

    try:
        out = subprocess.check_output(
            [
                YTDLP,
                query,
                "--flat-playlist",
                "--dump-single-json",
                "--no-playlist",
                "--skip-download",
            ],
            text=True,
            timeout=45,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return []

    try:
        payload = json.loads(out)
    except json.JSONDecodeError:
        return []

    candidates: list[VideoCandidate] = []
    for entry in payload.get("entries") or []:
        video_id = entry.get("id")
        title = entry.get("title")
        channel = entry.get("channel") or entry.get("uploader")
        if not video_id or not title or not channel:
            continue
        candidates.append(
            VideoCandidate(
                video_id=video_id,
                title=title,
                channel=channel,
            )
        )
    return candidates


def pick_best_video(exercise_name: str) -> VideoCandidate | None:
    """Walk priority channels top-to-bottom; take the first valid match for this exercise."""
    for preferred_channel in PRIORITY_CHANNELS:
        query = (
            f"ytsearch{SEARCH_RESULT_COUNT}:"
            f"{preferred_channel} {exercise_name} how to form technique"
        )
        for candidate in search_youtube(query):
            if title_rejected(candidate.title):
                continue
            if not title_matches_exercise(candidate.title, exercise_name):
                continue
            if not channel_matches(candidate.channel, preferred_channel):
                continue
            return candidate
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only process the top N exercises after popularity ordering",
    )
    parser.add_argument(
        "--sleep",
        type=float,
        default=0.15,
        help="Delay between YouTube searches",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Keep existing mappings and skip exercises already covered",
    )
    parser.add_argument(
        "--checkpoint-every",
        type=int,
        default=5,
        help="Write the catalog every N newly mapped exercises",
    )
    parser.add_argument(
        "--no-progress",
        action="store_true",
        help="Disable the live progress bar",
    )
    args = parser.parse_args()

    ascend = json.loads(ASCEND_CACHE.read_text()) if ASCEND_CACHE.exists() else []
    bundled = json.loads(BUNDLED_CATALOG.read_text())["exercises"]
    targets = build_targets(bundled, args.limit)

    mappings, done_ids, done_keys = load_existing_mappings() if args.resume else ([], set(), set())
    skipped: list[str] = []
    rejected: list[str] = []
    new_since_checkpoint = 0
    total = len(targets)
    progress = ProgressBar(total, enabled=not args.no_progress)
    progress.set_counts(len(mappings), 0, 0)

    for index, target in enumerate(targets, start=1):
        key = (norm(target.name), target.equipment)
        if target.bundled_catalog_id in done_ids or key in done_keys:
            progress.advance(index, f"resume {target.name[:24]}")
            continue

        candidate = pick_best_video(target.name)
        time.sleep(args.sleep)
        if not candidate:
            skipped.append(target.name)
            progress.advance(
                index,
                f"no match {target.name[:24]}",
                mapped=len(mappings),
                skipped=len(skipped),
                rejected=len(rejected),
            )
            continue

        meta = verify_oembed(candidate.video_id)
        time.sleep(0.04)
        if not meta:
            rejected.append(f"{target.name}:{candidate.video_id}")
            progress.advance(
                index,
                f"dead url {target.name[:24]}",
                mapped=len(mappings),
                skipped=len(skipped),
                rejected=len(rejected),
            )
            continue

        entry = {
            "exerciseId": target.bundled_catalog_id,
            "bundledCatalogID": target.bundled_catalog_id,
            "exerciseName": target.name,
            "equipment": target.equipment,
            "youtubeVideoId": candidate.video_id,
            "title": meta["title"],
            "channel": meta["channel"],
            "verifiedAt": time.strftime("%Y-%m-%d"),
        }
        mappings.append(entry)
        done_ids.add(target.bundled_catalog_id)
        done_keys.add(key)
        new_since_checkpoint += 1
        progress.advance(
            index,
            f"✓ {target.name[:24]} · {meta['channel'][:16]}",
            mapped=len(mappings),
            skipped=len(skipped),
            rejected=len(rejected),
        )

        if new_since_checkpoint >= args.checkpoint_every:
            write_catalog(
                mappings,
                len(bundled),
                len(ascend),
                skipped,
                rejected,
                progress=progress,
            )
            new_since_checkpoint = 0

    write_catalog(mappings, len(bundled), len(ascend), skipped, rejected, progress=progress)
    progress.finish()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
