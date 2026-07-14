#!/usr/bin/env python3
"""Generate Rep's deterministic, offline exercise catalog.

The source revision and digest are intentionally pinned. Only factual taxonomy is
imported: names, muscle groups, equipment, and category-derived measurement types.
Upstream instructions and images are excluded from the generated app resource.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import urllib.request
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIRECTORY = ROOT / "Rep" / "Resources" / "Catalog"

SOURCE_REVISION = "b0eed061e1c832b3ed815fbaa4b45b3cdc14df49"
SOURCE_PUBLISHED_AT = "2026-05-24T03:09:39Z"
SOURCE_URL = (
    "https://raw.githubusercontent.com/yuhonas/free-exercise-db/"
    f"{SOURCE_REVISION}/dist/exercises.json"
)
SOURCE_SHA256 = "d68a817484964095e6af0be2cdcbcc2c2504168d1d190c7d5c725ce52f3ae1f4"
LICENSE_URL = (
    "https://raw.githubusercontent.com/yuhonas/free-exercise-db/"
    f"{SOURCE_REVISION}/LICENSE.md"
)
LICENSE_SHA256 = "6b0382b16279f26ff69014300541967a356a666eb0b91b422f6862f6b7dad17e"

CATALOG_VERSION = "2026.05.24.2"
PAYLOAD_FILENAME = "rep-exercise-catalog-v1.json"
MANIFEST_FILENAME = "rep-exercise-catalog-manifest-v1.json"
LICENSE_FILENAME = "free-exercise-db-UNLICENSE.txt"

MEASUREMENT_OVERRIDES = {
    "Bear_Crawl_Sled_Drags": "distanceAndDuration",
    "Bench_Sprint": "distanceAndDuration",
    "Farmers_Walk": "distanceAndDuration",
    "Power_Stairs": "distanceAndDuration",
    "Prowler_Sprint": "distanceAndDuration",
    "Rickshaw_Carry": "distanceAndDuration",
    "Side_Hop-Sprint": "distanceAndDuration",
    "Single-Cone_Sprint_Drill": "distanceAndDuration",
    "Sled_Drag_-_Harness": "distanceAndDuration",
    "Sled_Overhead_Backward_Walk": "distanceAndDuration",
    "Sled_Push": "distanceAndDuration",
    "Wind_Sprints": "distanceAndDuration",
    "Yoke_Walk": "distanceAndDuration",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "RepCatalogBuilder/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def verified(data: bytes, expected_digest: str, label: str) -> bytes:
    actual_digest = sha256(data)
    if actual_digest != expected_digest:
        raise SystemExit(
            f"{label} digest mismatch: expected {expected_digest}, got {actual_digest}"
        )
    return data


def muscle_group(raw_value: str) -> str:
    value = raw_value.casefold()
    if value == "chest":
        return "chest"
    if value in {"lats", "middle back", "lower back", "traps"}:
        return "back"
    if value == "shoulders":
        return "shoulders"
    if value in {"biceps", "forearms"}:
        return "biceps"
    if value == "triceps":
        return "triceps"
    if value in {"quadriceps", "adductors", "abductors"}:
        return "quadriceps"
    if value == "hamstrings":
        return "hamstrings"
    if value == "glutes":
        return "glutes"
    if value == "calves":
        return "calves"
    if value == "abdominals":
        return "core"
    return "other"


def equipment(raw_value: str | None) -> str:
    value = (raw_value or "").casefold()
    if value == "barbell" or value == "e-z curl bar":
        return "barbell"
    if value == "dumbbell":
        return "dumbbell"
    if value == "machine":
        return "machine"
    if value == "cable":
        return "cable"
    if value == "body only":
        return "bodyweight"
    if value == "kettlebells":
        return "kettlebell"
    return "other"


def measurement_type(record: dict[str, Any], mapped_equipment: str) -> str:
    source_id = str(record["id"]).strip()
    if source_id in MEASUREMENT_OVERRIDES:
        return MEASUREMENT_OVERRIDES[source_id]

    name = record["name"].casefold()
    category = record.get("category", "").casefold()

    if category == "cardio":
        return "distanceAndDuration"
    if category == "stretching":
        return "duration"
    if mapped_equipment == "bodyweight":
        timed_terms = ("plank", "hold", "stretch", "pose", "wall sit", "isometric", "yoga")
        if any(term in name for term in timed_terms):
            return "duration"
        return "bodyweightAndRepetitions"
    return "weightAndRepetitions"


def unique(values: list[str]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        cleaned = value.strip()
        key = cleaned.casefold()
        if cleaned and key not in seen:
            result.append(cleaned)
            seen.add(key)
    return result


def transform(record: dict[str, Any]) -> dict[str, Any]:
    source_id = str(record["id"]).strip()
    name = str(record["name"]).strip()
    primary_values = [str(value) for value in record.get("primaryMuscles", [])]
    secondary_values = [str(value) for value in record.get("secondaryMuscles", [])]
    raw_equipment = record.get("equipment")

    if not source_id or not name or not primary_values:
        raise ValueError(f"Source record is missing required taxonomy: {record!r}")

    primary = muscle_group(primary_values[0])
    secondary = unique(
        [muscle_group(value) for value in primary_values[1:] + secondary_values]
    )
    secondary = [value for value in secondary if value != primary]
    mapped_equipment = equipment(raw_equipment)
    aliases = unique(
        primary_values
        + secondary_values
        + ([str(raw_equipment)] if raw_equipment else [])
    )

    return {
        "id": f"rep:free-exercise-db:{source_id}",
        "name": name,
        "primaryMuscleGroup": primary,
        "secondaryMuscleGroups": secondary,
        "equipment": mapped_equipment,
        "measurementType": measurement_type(record, mapped_equipment),
        "searchAliases": aliases,
    }


def catalog_payload(source_data: bytes) -> dict[str, Any]:
    source_records = json.loads(source_data)
    if not isinstance(source_records, list) or len(source_records) < 800:
        raise ValueError("Expected at least 800 source exercise records")

    exercises = sorted((transform(record) for record in source_records), key=lambda item: item["id"])
    ids = [exercise["id"] for exercise in exercises]
    normalized_names = [exercise["name"].strip().casefold() for exercise in exercises]
    if len(ids) != len(set(ids)):
        raise ValueError("Generated catalog contains duplicate stable IDs")
    if len(normalized_names) != len(set(normalized_names)):
        raise ValueError("Generated catalog contains duplicate normalized names")

    return {"schemaVersion": 1, "exercises": exercises}


def encoded_json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=pathlib.Path,
        help="Use a local exercises.json instead of downloading the pinned revision.",
    )
    parser.add_argument(
        "--output-directory",
        type=pathlib.Path,
        default=DEFAULT_OUTPUT_DIRECTORY,
    )
    args = parser.parse_args()

    source_data = args.source.read_bytes() if args.source else download(SOURCE_URL)
    verified(source_data, SOURCE_SHA256, "Exercise dataset")
    license_data = verified(download(LICENSE_URL), LICENSE_SHA256, "Dataset license")

    payload = catalog_payload(source_data)
    payload_data = encoded_json(payload)
    manifest = {
        "schemaVersion": 1,
        "catalogVersion": CATALOG_VERSION,
        "publishedAt": SOURCE_PUBLISHED_AT,
        "payloadFilename": PAYLOAD_FILENAME,
        "itemCount": len(payload["exercises"]),
        "payloadSHA256": sha256(payload_data),
        "source": {
            "name": "Free Exercise DB",
            "url": "https://github.com/yuhonas/free-exercise-db",
            "revision": SOURCE_REVISION,
            "sourceSHA256": SOURCE_SHA256,
            "license": "Unlicense",
            "licenseURL": LICENSE_URL,
        },
        "contentPolicy": {
            "included": ["exercise names", "muscle taxonomy", "equipment taxonomy"],
            "excluded": ["instructions", "images"],
        },
    }

    args.output_directory.mkdir(parents=True, exist_ok=True)
    (args.output_directory / PAYLOAD_FILENAME).write_bytes(payload_data)
    (args.output_directory / MANIFEST_FILENAME).write_bytes(encoded_json(manifest))
    (args.output_directory / LICENSE_FILENAME).write_bytes(license_data)

    print(
        f"Generated {len(payload['exercises'])} exercises; "
        f"payload SHA-256 {manifest['payloadSHA256']}"
    )


if __name__ == "__main__":
    main()
