#!/usr/bin/env python3
"""Audit curated seed exercises against AscendAPI GIF availability."""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import unicodedata
import urllib.parse
from dataclasses import dataclass

API_BASE = "https://oss.exercisedb.dev/api/v1/exercises"
SCORE_THRESHOLD = 200
POPULARITY_CUTOFF = 85

SEEDS = [
    ("Barbell Bench Press", "chest", "barbell", 1),
    ("Incline Barbell Bench Press", "chest", "barbell", 13),
    ("Dumbbell Bench Press", "chest", "dumbbell", 12),
    ("Incline Dumbbell Press", "chest", "dumbbell", 14),
    ("Machine Chest Press", "chest", "machine", 39),
    ("Cable Fly", "chest", "cable", 38),
    ("Push-Up", "chest", "bodyweight", 6),
    ("Pull-Up", "back", "bodyweight", 5),
    ("Chin-Up", "back", "bodyweight", 29),
    ("Lat Pulldown", "back", "cable", 11),
    ("Barbell Row", "back", "barbell", 9),
    ("One-Arm Dumbbell Row", "back", "dumbbell", 51),
    ("Seated Cable Row", "back", "cable", 23),
    ("Chest-Supported Row", "back", "machine", 52),
    ("Face Pull", "shoulders", "cable", 31),
    ("Barbell Overhead Press", "shoulders", "barbell", 7),
    ("Dumbbell Shoulder Press", "shoulders", "dumbbell", 17),
    ("Machine Shoulder Press", "shoulders", "machine", 40),
    ("Dumbbell Lateral Raise", "shoulders", "dumbbell", 22),
    ("Cable Lateral Raise", "shoulders", "cable", 54),
    ("Reverse Pec Deck", "shoulders", "machine", 53),
    ("Barbell Curl", "biceps", "barbell", 18),
    ("Dumbbell Curl", "biceps", "dumbbell", 19),
    ("Hammer Curl", "biceps", "dumbbell", 28),
    ("Cable Curl", "biceps", "cable", 43),
    ("Triceps Pushdown", "triceps", "cable", 20),
    ("Overhead Triceps Extension", "triceps", "cable", 42),
    ("Skull Crusher", "triceps", "barbell", 41),
    ("Assisted Dip", "triceps", "machine", 62),
    ("Back Squat", "quadriceps", "barbell", 3),
    ("Front Squat", "quadriceps", "barbell", 27),
    ("Leg Press", "quadriceps", "machine", 16),
    ("Leg Extension", "quadriceps", "machine", 24),
    ("Bulgarian Split Squat", "quadriceps", "dumbbell", 35),
    ("Walking Lunge", "quadriceps", "dumbbell", 36),
    ("Romanian Deadlift", "hamstrings", "barbell", 15),
    ("Seated Leg Curl", "hamstrings", "machine", 26),
    ("Lying Leg Curl", "hamstrings", "machine", 25),
    ("Barbell Hip Thrust", "glutes", "barbell", 32),
    ("Cable Glute Kickback", "glutes", "cable", 55),
    ("Standing Calf Raise", "calves", "machine", 44),
    ("Seated Calf Raise", "calves", "machine", 45),
    ("Plank", "core", "bodyweight", 46),
    ("Hanging Leg Raise", "core", "bodyweight", 47),
    ("Cable Crunch", "core", "cable", 48),
    ("Ab Wheel Rollout", "core", "other", 59),
    ("Deadlift", "fullBody", "barbell", 4),
    ("Sumo Deadlift", "fullBody", "barbell", 49),
    ("Kettlebell Swing", "fullBody", "kettlebell", 50),
    ("Farmer Carry", "fullBody", "dumbbell", 58),
    ("Goblet Squat", "quadriceps", "kettlebell", 34),
    ("Smith Machine Squat", "quadriceps", "smithMachine", 60),
    ("Smith Machine Bench Press", "chest", "smithMachine", 61),
    ("Dip", "chest", "bodyweight", 30),
    ("Weighted Pull-Up", "back", "bodyweight", 57),
]

ENRICH_QUERIES = {
    "Ab Wheel Rollout": ["ab wheel", "wheel rollout", "ab roller"],
    "Chest-Supported Row": ["chest supported row", "seal row"],
    "Reverse Pec Deck": ["reverse fly machine", "rear delt machine"],
    "Cable Glute Kickback": ["cable kickback", "glute kickback"],
    "Farmer Carry": ["farmer walk", "farmer carry"],
    "Smith Machine Squat": ["smith machine squat"],
    "Smith Machine Bench Press": ["smith machine bench press"],
    "Assisted Dip": ["assisted dip", "assisted chest dip"],
    "Skull Crusher": ["skull crusher", "lying triceps extension"],
    "Face Pull": ["face pull"],
    "Bulgarian Split Squat": ["bulgarian split squat"],
    "Walking Lunge": ["walking lunge", "dumbbell lunge"],
    "Hanging Leg Raise": ["hanging leg raise"],
    "Cable Crunch": ["cable crunch", "kneeling cable crunch"],
    "Push-Up": ["push up", "push-up"],
    "Pull-Up": ["pull up", "pull-up"],
    "Chin-Up": ["chin up", "chin-up"],
    "Dip": ["chest dip", "dip"],
    "Weighted Pull-Up": ["weighted pull up", "weighted pull-up"],
    "Plank": ["front plank", "plank"],
}


def normalize_name(name: str) -> str:
    return " ".join(name.casefold().split())


def normalized_search_text(value: str) -> str:
    folded = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii").casefold()
    sanitized = re.sub(r"[^a-z0-9]+", " ", folded)
    return " ".join(sanitized.split())


def map_equipment(values: list[str]) -> str:
    norm = [normalized_search_text(v) for v in values]
    if "smith machine" in norm:
        return "smithMachine"
    if "kettlebell" in norm:
        return "kettlebell"
    if "dumbbell" in norm:
        return "dumbbell"
    if any(v in norm for v in ("barbell", "olympic barbell", "ez barbell", "trap bar")):
        return "barbell"
    if "cable" in norm:
        return "cable"
    if "body weight" in norm:
        return "bodyweight"
    if "assisted" in norm or any("machine" in v for v in norm):
        return "machine"
    return "other"


def map_muscle(raw: str) -> str | None:
    key = normalized_search_text(raw)
    table = {
        "pectorals": "chest", "chest": "chest", "upper chest": "chest",
        "latissimus dorsi": "back", "lats": "back", "back": "back", "upper back": "back",
        "deltoids": "shoulders", "delts": "shoulders", "shoulders": "shoulders",
        "biceps": "biceps", "triceps": "triceps",
        "quadriceps": "quadriceps", "quads": "quadriceps",
        "hamstrings": "hamstrings", "glutes": "glutes",
        "calves": "calves", "abs": "core", "abdominals": "core", "core": "core",
        "cardiovascular system": "fullBody",
    }
    return table.get(key)


def mapped_primary(candidate: dict) -> str | None:
    for muscle in candidate.get("targetMuscles", []):
        mapped = map_muscle(muscle)
        if mapped:
            return mapped
    for part in candidate.get("bodyParts", []):
        mapped = map_muscle(part)
        if mapped:
            return mapped
    return None


def candidate_score(candidate: dict, seed_name: str, muscle: str, equipment: str) -> int:
    wanted_name = normalized_search_text(seed_name)
    wanted_tokens = set(wanted_name.split())
    candidate_name = normalized_search_text(candidate["name"])
    candidate_tokens = set(candidate_name.split())
    score = len(wanted_tokens & candidate_tokens) * 100
    if candidate_name == wanted_name:
        score += 10_000
    elif candidate_name.startswith(wanted_name) or wanted_name.startswith(candidate_name):
        score += 1_000
    elif wanted_name in candidate_name:
        score += 500
    mapped_eq = map_equipment(candidate.get("equipments", []))
    if mapped_eq == equipment:
        score += 80
    mapped_muscle = mapped_primary(candidate)
    if mapped_muscle == muscle:
        score += 60
    return score


def fetch_json(url: str, retries: int = 8) -> dict:
    for attempt in range(retries):
        result = subprocess.run(["curl", "-s", url], capture_output=True, text=True)
        body = result.stdout.strip()
        if body:
            try:
                return json.loads(body)
            except json.JSONDecodeError:
                pass
        time.sleep(min(8, 0.75 * (attempt + 1)))
    raise RuntimeError(f"Failed to fetch {url}")


def download_catalog() -> list[dict]:
    catalog: list[dict] = []
    cursor = None
    seen: set[str] = set()
    while True:
        params = {"limit": "100"}
        if cursor:
            params["after"] = cursor
        url = API_BASE + "?" + urllib.parse.urlencode(params)
        page = fetch_json(url)
        data = page.get("data", [])
        catalog.extend(data)
        meta = page.get("meta", {})
        print(f"Fetched {len(catalog)} / {meta.get('total', '?')}", file=sys.stderr)
        if not meta.get("hasNextPage") or not data:
            break
        last_id = data[-1]["exerciseId"]
        if last_id in seen:
            break
        seen.add(last_id)
        cursor = last_id
        time.sleep(0.45)
    return catalog


def best_match(seed_name: str, muscle: str, equipment: str, catalog: list[dict]) -> tuple[dict | None, int]:
    queries = [seed_name] + ENRICH_QUERIES.get(seed_name, [])
    query_tokens: set[str] = set()
    for query in queries:
        query_tokens.update(normalized_search_text(query).split())

    candidates = [
        item
        for item in catalog
        if query_tokens & set(normalized_search_text(item["name"]).split())
    ]
    if not candidates:
        return None, 0
    best = max(candidates, key=lambda c: candidate_score(c, seed_name, muscle, equipment))
    return best, candidate_score(best, seed_name, muscle, equipment)


@dataclass
class AuditRow:
    seed: str
    rank: int
    status: str
    score: int
    match_name: str | None
    match_id: str | None
    gif: str | None


def main() -> int:
    print("Downloading catalog...", file=sys.stderr)
    catalog = download_catalog()
    rows: list[AuditRow] = []
    for seed_name, muscle, equipment, rank in SEEDS:
        best, score = best_match(seed_name, muscle, equipment, catalog)
        if best and score >= SCORE_THRESHOLD:
            if normalize_name(best["name"]) == normalize_name(seed_name):
                status = "exact"
            elif score >= 1000:
                status = "strong"
            else:
                status = "fuzzy"
            rows.append(
                AuditRow(seed_name, rank, status, score, best["name"], best["exerciseId"], best.get("gifUrl"))
            )
        else:
            rows.append(AuditRow(seed_name, rank, "missing", score, None, None, None))

    missing = [r for r in rows if r.status == "missing"]
    fuzzy = [r for r in rows if r.status == "fuzzy"]
    weak_fuzzy = [r for r in fuzzy if r.score < 300]

    print("# Seed media audit\n")
    print(f"Catalog size: {len(catalog)}")
    print(f"Total seeds: {len(rows)}")
    print(f"Exact/strong matches: {len([r for r in rows if r.status in ('exact', 'strong')])}")
    print(f"Fuzzy matches (score>={SCORE_THRESHOLD}): {len(fuzzy)}")
    print(f"Missing matches: {len(missing)}\n")

    print("## Missing GIF matches")
    for r in sorted(missing, key=lambda x: x.rank):
        print(f"- [{r.rank:02d}] {r.seed} (best score {r.score})")

    print("\n## Weak fuzzy matches (score < 300)")
    for r in sorted(weak_fuzzy, key=lambda x: x.rank):
        print(f"- [{r.rank:02d}] {r.seed} -> {r.match_name} (score {r.score}, id {r.match_id})")

    print("\n## Fuzzy matches needing alias/query fix")
    for r in sorted(fuzzy, key=lambda x: x.rank):
        if r.score >= 300:
            print(f"- [{r.rank:02d}] {r.seed} -> {r.match_name} (score {r.score}, id {r.match_id})")

    print("\n## Low-popularity missing (removal candidates)")
    for r in sorted([x for x in missing if x.rank >= POPULARITY_CUTOFF], key=lambda x: x.rank):
        print(f"- [{r.rank:02d}] {r.seed}")

    print("\n## Low-popularity fuzzy (review/remove)")
    for r in sorted([x for x in fuzzy if x.rank >= POPULARITY_CUTOFF], key=lambda x: x.rank):
        print(f"- [{r.rank:02d}] {r.seed} -> {r.match_name} (score {r.score})")

    print("\n## JSON")
    print(json.dumps([r.__dict__ for r in rows], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
