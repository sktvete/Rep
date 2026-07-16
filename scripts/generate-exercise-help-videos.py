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

EQUIP_MAP = {
    "barbell": "barbell",
    "body weight": "bodyweight",
    "cable": "cable",
    "dumbbell": "dumbbell",
    "machine": "machine",
    "smith machine": "smithMachine",
    "kettlebell": "kettlebell",
    "leverage machine": "machine",
    "ez barbell": "barbell",
    "assisted": "other",
    "band": "other",
    "stability ball": "other",
    "rope": "cable",
    "weighted": "other",
    "medicine ball": "other",
    "olympic barbell": "barbell",
    "trap bar": "barbell",
    "resistance band": "other",
    "sled machine": "machine",
}

DEFAULT_EQUIPMENT = {
    "squat": "barbell",
    "back squat": "barbell",
    "deadlift": "barbell",
    "sumo deadlift": "barbell",
    "front squat": "barbell",
    "barbell overhead press": "barbell",
    "overhead press": "barbell",
    "barbell row": "barbell",
    "bent over row": "barbell",
    "lat pulldown": "cable",
    "seated cable row": "cable",
    "triceps pushdown": "cable",
    "tricep pushdown": "cable",
    "cable fly": "cable",
    "cable curl": "cable",
    "cable lateral raise": "cable",
    "cable crunch": "cable",
    "cable glute kickback": "cable",
    "face pull": "cable",
    "leg press": "machine",
    "leg extension": "machine",
    "lying leg curl": "machine",
    "seated leg curl": "machine",
    "machine chest press": "machine",
    "machine shoulder press": "machine",
    "standing calf raise": "machine",
    "seated calf raise": "machine",
    "reverse pec deck": "machine",
    "smith machine squat": "smithMachine",
    "assisted dip": "machine",
    "pull up": "bodyweight",
    "push up": "bodyweight",
    "chin up": "bodyweight",
    "dip": "bodyweight",
    "plank": "bodyweight",
    "hanging leg raise": "bodyweight",
    "ab wheel rollout": "bodyweight",
    "weighted pull up": "other",
    "farmer carry": "other",
    "kettlebell swing": "kettlebell",
    "goblet squat": "kettlebell",
}

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
YTDLP = shutil.which("yt-dlp") or str(
    Path.home() / "Library/Python/3.9/bin/yt-dlp"
)


@dataclass(frozen=True)
class ExerciseTarget:
    name: str
    equipment: str


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


def infer_equipment(name: str) -> str:
    return DEFAULT_EQUIPMENT.get(norm(name), "other")


def resolve_exercise_id(
    name: str,
    equipment: str,
    by_name_eq_ascend: dict[tuple[str, str], list[dict]],
    by_name_eq_bundled: dict[tuple[str, str], dict],
) -> tuple[str, str | None]:
    key = (norm(name), equipment)
    ascend_hits = by_name_eq_ascend.get(key, [])
    ascend_id = None
    if len(ascend_hits) == 1:
        ascend_id = ascend_hits[0]["exerciseId"]
    elif len(ascend_hits) > 1:
        exact = [hit for hit in ascend_hits if norm(hit["name"]) == norm(name)]
        if len(exact) == 1:
            ascend_id = exact[0]["exerciseId"]

    bundled_rec = by_name_eq_bundled.get(key)
    exercise_id = ascend_id or (
        bundled_rec["id"]
        if bundled_rec
        else f"rep:local:{norm(name).replace(' ', '-')}"
    )
    bundled_catalog_id = bundled_rec["id"] if bundled_rec else None
    return exercise_id, bundled_catalog_id


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


def build_targets(limit: int | None) -> list[ExerciseTarget]:
    names = load_popular_exercise_names()
    if limit is not None:
        names = names[:limit]

    targets: list[ExerciseTarget] = []
    seen: set[tuple[str, str]] = set()
    for name in names:
        equipment = infer_equipment(name)
        key = (norm(name), equipment)
        if key in seen:
            continue
        seen.add(key)
        targets.append(ExerciseTarget(name=name, equipment=equipment))
    return targets


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only process the top N popular exercises",
    )
    parser.add_argument(
        "--sleep",
        type=float,
        default=0.15,
        help="Delay between YouTube searches",
    )
    args = parser.parse_args()

    ascend = json.loads(ASCEND_CACHE.read_text()) if ASCEND_CACHE.exists() else []
    bundled = json.loads(BUNDLED_CATALOG.read_text())["exercises"]

    by_name_eq_ascend: dict[tuple[str, str], list[dict]] = {}
    for item in ascend:
        equipment = EQUIP_MAP.get((item.get("equipments") or ["other"])[0].lower(), "other")
        by_name_eq_ascend.setdefault((norm(item["name"]), equipment), []).append(item)

    by_name_eq_bundled = {
        (norm(item["name"]), item["equipment"]): item for item in bundled
    }

    mappings = []
    skipped: list[str] = []
    rejected: list[str] = []
    used_exercise_ids: set[str] = set()

    for target in build_targets(args.limit):
        candidate = pick_best_video(target.name)
        time.sleep(args.sleep)
        if not candidate:
            skipped.append(target.name)
            continue

        meta = verify_oembed(candidate.video_id)
        time.sleep(0.04)
        if not meta:
            rejected.append(f"{target.name}:{candidate.video_id}")
            continue

        exercise_id, bundled_catalog_id = resolve_exercise_id(
            target.name,
            target.equipment,
            by_name_eq_ascend,
            by_name_eq_bundled,
        )
        if exercise_id in used_exercise_ids:
            continue
        used_exercise_ids.add(exercise_id)

        entry = {
            "exerciseId": exercise_id,
            "exerciseName": target.name,
            "equipment": target.equipment,
            "youtubeVideoId": candidate.video_id,
            "title": meta["title"],
            "channel": meta["channel"],
            "verifiedAt": time.strftime("%Y-%m-%d"),
        }
        if bundled_catalog_id:
            entry["bundledCatalogID"] = bundled_catalog_id
        mappings.append(entry)
        print(
            f"✓ {target.name:32} -> {meta['channel']:24} | {meta['title'][:70]}"
        )

    payload = {
        "schemaVersion": 1,
        "catalogVersion": time.strftime("%Y.%m.%d.1"),
        "publishedAt": time.strftime("%Y-%m-%dT00:00:00Z"),
        "ascendApiExerciseCount": len(ascend) or 1500,
        "mappings": mappings,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"\nWrote {len(mappings)} mappings to {OUTPUT}")
    if skipped:
        print(f"Skipped ({len(skipped)}): {', '.join(skipped)}")
    if rejected:
        print("Rejected:")
        for item in rejected:
            print(f"  {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
