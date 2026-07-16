#!/usr/bin/env python3
"""Validate the bundled exercise help video catalog."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "Rep/Resources/Catalog/exercise-help-videos-v1.json"
YOUTUBE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,11}$")
REQUIRED_FIELDS = (
    "exerciseId",
    "exerciseName",
    "youtubeVideoId",
    "title",
    "channel",
    "verifiedAt",
)


def verify_youtube(video_id: str) -> tuple[bool, str | None]:
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
            return False, f"HTTP {code}"
        meta = json.loads(body)
        return True, meta.get("title")
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--skip-url-check", action="store_true")
    args = parser.parse_args()

    payload = json.loads(args.catalog.read_text())
    mappings = payload.get("mappings", [])
    ascend_total = payload.get("ascendApiExerciseCount")

    duplicate_ids: list[str] = []
    invalid_ids: list[str] = []
    missing_fields: list[str] = []
    dead_urls: list[str] = []
    seen: set[str] = set()

    for mapping in mappings:
        exercise_id = mapping.get("exerciseId", "")
        if not exercise_id:
            missing_fields.append("<missing exerciseId>")
            continue
        if exercise_id in seen:
            duplicate_ids.append(exercise_id)
        seen.add(exercise_id)

        for field in REQUIRED_FIELDS:
            value = mapping.get(field)
            if not isinstance(value, str) or not value.strip():
                missing_fields.append(f"{exercise_id}:{field}")

        video_id = mapping.get("youtubeVideoId", "")
        if not YOUTUBE_ID_RE.fullmatch(video_id or ""):
            invalid_ids.append(f"{exercise_id}:{video_id}")

        if not args.skip_url_check and YOUTUBE_ID_RE.fullmatch(video_id or ""):
            ok, detail = verify_youtube(video_id)
            if not ok:
                dead_urls.append(f"{exercise_id}:{video_id}:{detail}")
            time.sleep(0.04)

    mapped = len(mappings)
    verified_live = mapped - len(dead_urls)
    gaps = (ascend_total or 0) - mapped if ascend_total else None

    print(f"Catalog: {args.catalog}")
    print(f"AscendAPI exercises: {ascend_total if ascend_total is not None else 'unknown'}")
    print(f"Mapped exercises: {mapped}")
    print(f"Verified live videos: {verified_live}")
    print(f"Duplicate exercise IDs: {len(duplicate_ids)}")
    print(f"Invalid YouTube IDs: {len(invalid_ids)}")
    print(f"Missing required fields: {len(missing_fields)}")
    print(f"Dead URLs: {len(dead_urls)}")
    if gaps is not None:
        print(f"Remaining coverage gaps: {max(gaps, 0)}")

    if duplicate_ids:
        print("\nDuplicates:")
        for item in duplicate_ids:
            print(f"  - {item}")
    if invalid_ids:
        print("\nInvalid YouTube IDs:")
        for item in invalid_ids:
            print(f"  - {item}")
    if missing_fields:
        print("\nMissing fields:")
        for item in missing_fields:
            print(f"  - {item}")
    if dead_urls:
        print("\nDead URLs:")
        for item in dead_urls:
            print(f"  - {item}")

    failed = duplicate_ids or invalid_ids or missing_fields or dead_urls
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
