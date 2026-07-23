#!/usr/bin/env python3
"""Generate the bundled exercise help video catalog.

Prefers short, modern, helpful form demos over long/clickbait uploads.
Candidates are scored globally (duration, recency, title quality, channel
trust, relevance) instead of taking the first hit from a fixed channel list.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASCEND_CACHE = Path("/tmp/rep-ascend/all-unique.json")
BUNDLED_CATALOG = ROOT / "Rep/Resources/Catalog/rep-exercise-catalog-v1.json"
OUTPUT = ROOT / "Rep/Resources/Catalog/exercise-help-videos-v1.json"
POPULARITY_SOURCE = ROOT / "Rep/Shared/ExercisePopularity.swift"

# Trusted coaches / demo channels. Bonus only — never a hard gate.
PRIORITY_CHANNELS = [
    "Jeff Nippard",
    "Jeremy Ethier",
    "Squat University",
    "E3 Rehab",
    "Menno Henselmans",
    "Renaissance Periodization",
    "2 Minute Tutorials",
    "MuscleWiki",
    "FitnessFAQs",
    "Hybrid Calisthenics",
    "Colossus Fitness",
    "ATHLEAN-X",
    "ScottHermanFitness",
    "Bodybuilding.com",
    "TylerPath",
    "StrongFirst",
]

# Hard reject — wrong movement, fear-bait, long-form essays, not a form demo.
REJECT_TITLE_PATTERNS = (
    r"\bstop\b",
    r"\bwaste\b",
    r"\bwrong\b",
    r"\bmistakes?\b",
    r"\bnever\b",
    r"\bvs\.?\b",
    r"\bversus\b",
    r"\bchallenge\b",
    r"\btransformation\b",
    r"\bmotivation\b",
    r"\bworkout\s+plan\b",
    r"\bfull\s+workout\b",
    r"\bsample\s+program\b",
    r"\bprogram\b",
    r"\bscience[- ]based\b",
    r"\baccording\s+to\s+science\b",
    r"\bblow\s+up\b",
    r"\bhuge\b",
    r"\bbigger\b",
    r"\bgrow(?:th|ing)?\b",
    r"\bsteps?\b",
    r"\bday\s+\d+\b",
    r"\bhumou?r\b",
    r"\bfunny\b",
    r"\bprank\b",
    r"\breaction\b",
    r"\bpodcast\b",
    r"\binterview\b",
    r"\bstudy\b",
    r"#\d+",
)

# Soft reject — allowed but heavily penalized.
WEAK_TITLE_PATTERNS = (
    r"\btop\s+\d+\b",
    r"\bbest\s+\d+\b",
    r"\bsecrets?\b",
    r"\bhacks?\b",
    r"\bgains?\b",
    r"\bshocking\b",
    r"\byou.?re\s+doing\b",
    r"\bperfect\s+technique\b",
    r"\boptimal\b",
)

HELPFUL_TITLE_PATTERNS = (
    r"\bhow\s+to\b",
    r"\bform\b",
    r"\btechnique\b",
    r"\btutorial\b",
    r"\bdemo(?:nstration)?\b",
    r"\bcue[s]?\b",
    r"\bproper\b",
    r"\bcorrect\b",
    r"\binstruction[s]?\b",
    r"\bbreakdown\b",
    r"\bsetup\b",
)

SHORT_HINT_PATTERNS = (
    r"\bshort\b",
    r"\bquick\b",
    r"\bshorts?\b",
    r"\b2\s*minute\b",
    r"\b1\s*minute\b",
    r"\b60\s*sec",
    r"\b\d+\s*(?:sec|secs|second|seconds)\b",
    r"\bin\s+\d+\b",
    r"\bno\s+talk(?:ing)?\b",
    r"\bsilent\b",
    r"\bdemo\b",
)

SEARCH_RESULT_COUNT = 25
ENRICH_TOP_N = 10
MIN_ACCEPT_SCORE = 60.0
# Prefer ~20–90s straight-to-form demos. Hard-cap rejects lecture intros.
IDEAL_DURATION_MIN = 15
IDEAL_DURATION_MAX = 90
SOFT_DURATION_MAX = 150
HARD_DURATION_MAX = 240
MAX_AGE_YEARS = 8
PROGRESS_WIDTH = 36
YTDLP = shutil.which("yt-dlp") or str(Path.home() / "Library/Python/3.9/bin/yt-dlp")


@dataclass(frozen=True)
class ExerciseTarget:
    name: str
    equipment: str
    exercise_id: str
    bundled_catalog_id: str | None = None


@dataclass
class VideoCandidate:
    video_id: str
    title: str
    channel: str
    duration: int | None = None
    upload_date: str | None = None  # YYYYMMDD
    view_count: int | None = None
    score: float = 0.0


def norm(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", " ", value.lower())
    return " ".join(cleaned.split())


def normalize_channel(value: str) -> str:
    cleaned = value.lower()
    cleaned = cleaned.replace("™", "").replace("®", "")
    cleaned = re.sub(r"[^a-z0-9]+", "", cleaned)
    return cleaned


def channel_matches(candidate_channel: str, preferred_channel: str) -> bool:
    normalized_candidate = normalize_channel(candidate_channel)
    normalized_preferred = normalize_channel(preferred_channel)
    if not normalized_candidate or not normalized_preferred:
        return False
    if normalized_candidate == normalized_preferred:
        return True
    return (
        normalized_preferred in normalized_candidate
        or normalized_candidate in normalized_preferred
    )


def channel_priority(channel: str) -> int | None:
    for index, preferred in enumerate(PRIORITY_CHANNELS):
        if channel_matches(channel, preferred):
            return index
    return None


def title_rejected(title: str) -> bool:
    lower = title.lower()
    return any(re.search(pattern, lower) for pattern in REJECT_TITLE_PATTERNS)


# Equipment / setup tokens that must not silently flip between exercise and video.
EQUIPMENT_TOKENS = {
    "barbell",
    "dumbbell",
    "dumbbells",
    "cable",
    "machine",
    "smith",
    "bodyweight",
    "band",
    "kettlebell",
    "trap",
    "hex",
    "ez",
}

# Variation tokens: if present in the title but not the exercise, reject.
VARIATION_TOKENS = {
    "incline",
    "decline",
    "flat",
    "seated",
    "standing",
    "lying",
    "prone",
    "sumo",
    "conventional",
    "front",
    "back",
    "overhead",
    "close",
    "wide",
    "single",
    "one",
    "assisted",
    "weighted",
    "paused",
    "deficit",
    "romanian",
    "stiff",
    "hack",
    "goblet",
    "bulgarian",
    "smith",
    "bodyweight",
    "machine",
    "wall",
    "box",
    "jump",
    "jumping",
    "pistol",
    "sissy",
    "hack",
    "landmine",
    "safety",
    "cossack",
    "chair",
    "air",
    "clean",
    "snatch",
    "overhead",
    "split",
    "zercher",
    "pause",
    "paused",
}

# Extra impostors often attached to squat/deadlift/press titles.
IMPOSTOR_PHRASES = (
    "at home",
    "chair squat",
    "air squat",
    "cossack",
    "squat clean",
    "clean squat",
    "wall sit",
    "wall squat",
    "box squat",
    "jump squat",
    "pistol squat",
    "split squat",
    "overhead squat",
    "goblet squat",
    "hack squat",
    "sissy squat",
)

MOVEMENT_ALIASES = {
    "press": {"press", "bench"},
    "bench": {"bench", "press"},
    "squat": {"squat", "squats"},
    "squats": {"squat", "squats"},
    "deadlift": {"deadlift", "deadlifts"},
    "deadlifts": {"deadlift", "deadlifts"},
    "row": {"row", "rows"},
    "rows": {"row", "rows"},
    "pull": {"pull", "pulldown", "pulldowns"},
    "pulldown": {"pulldown", "pulldowns", "pull"},
    "curl": {"curl", "curls"},
    "curls": {"curl", "curls"},
    "pushdown": {"pushdown", "pushdowns", "pressdown"},
    "raise": {"raise", "raises"},
    "lunge": {"lunge", "lunges"},
    "dip": {"dip", "dips"},
    "chin": {"chin", "chinup", "pull"},
}


def title_tokens(name: str) -> list[str]:
    """Content tokens used for fuzzy overlap (equipment handled separately)."""
    stopwords = {
        "a",
        "an",
        "and",
        "for",
        "of",
        "the",
        "to",
        "with",
        "how",
        "proper",
        "form",
        "technique",
        "tutorial",
        "demo",
        "demonstration",
        "exercise",
        "guide",
    }
    return [
        token
        for token in norm(name).split()
        if token not in stopwords and len(token) > 2
    ]


def _token_in_title(token: str, title_norm: str) -> bool:
    aliases = MOVEMENT_ALIASES.get(token, {token})
    title_parts = set(title_norm.split())
    return any(alias in title_parts or alias in title_norm for alias in aliases)


def title_match_ratio(title: str, exercise_name: str) -> float:
    tokens = [t for t in title_tokens(exercise_name) if t not in EQUIPMENT_TOKENS]
    if not tokens:
        return 1.0
    title_norm = norm(title)
    matches = sum(1 for token in tokens if _token_in_title(token, title_norm))
    return matches / len(tokens)


def title_equipment_conflict(
    title: str,
    exercise_name: str,
    equipment: str | None = None,
) -> str | None:
    """Return a reason if title implies a different setup than the exercise."""
    title_norm = norm(title)
    name_norm = norm(exercise_name)
    title_parts = set(title_norm.split())
    name_parts = set(name_norm.split())
    equipment_norm = norm(equipment or "")

    title_equip = {t for t in EQUIPMENT_TOKENS if t in title_parts}
    name_equip = {t for t in EQUIPMENT_TOKENS if t in name_parts}
    if equipment_norm in EQUIPMENT_TOKENS:
        name_equip.add(equipment_norm)
    if equipment_norm in {"smith machine", "smithmachine"}:
        name_equip.add("smith")

    if "dumbbells" in title_equip:
        title_equip.add("dumbbell")
    if "dumbbells" in name_equip:
        name_equip.add("dumbbell")

    for phrase in IMPOSTOR_PHRASES:
        phrase_norm = norm(phrase)
        # Only reject if the impostor isn't part of the exercise name itself.
        if phrase_norm in title_norm and phrase_norm not in name_norm:
            # "back squat" exercise may still mention squat clean? no — reject cleans always unless in name
            return f"impostor phrase '{phrase}'"

    if title_equip and name_equip and title_equip.isdisjoint(name_equip):
        return f"equipment {sorted(title_equip)} != {sorted(name_equip)}"

    # Ambiguous short names ("Squat", "Deadlift") with known barbell equipment must
    # show a barbell/back-squat cue — otherwise YouTube returns air/chair/PT demos.
    ambiguous_barbell = name_norm in {"squat", "deadlift", "row", "press", "overhead press"}
    if "barbell" in name_equip and ambiguous_barbell:
        barbell_cues = (
            "barbell" in title_norm
            or "back squat" in title_norm
            or "high bar" in title_norm
            or "low bar" in title_norm
            or "conventional" in title_norm
        )
        if not barbell_cues:
            return "missing barbell cue for barbell exercise"

    implied_barbell = (
        "back squat" in title_norm
        or "front squat" in title_norm
        or "high bar" in title_norm
        or "low bar" in title_norm
        or "conventional deadlift" in title_norm
    )
    required = name_equip - {"machine"}
    if required and not any(token in title_norm for token in required):
        if "barbell" in required and (ambiguous_barbell or implied_barbell):
            pass
        elif required != {"bodyweight"}:
            return f"missing equipment {sorted(required)}"

    for token in VARIATION_TOKENS:
        if token in title_parts and token not in name_parts:
            if token == "back" and "squat" in name_parts and "front" not in name_parts:
                continue
            if token == "flat" and "bench" in name_parts:
                continue
            if token == "conventional" and "deadlift" in name_parts:
                continue
            # high/low bar are barbell squat styles, OK for Squat / Back Squat
            if token in {"paused", "pause"}:
                return f"extra variation '{token}'"
            return f"extra variation '{token}'"

    for token in (
        "incline",
        "decline",
        "smith",
        "bodyweight",
        "goblet",
        "sumo",
        "romanian",
        "wall",
        "box",
        "jump",
        "pistol",
        "hack",
        "landmine",
        "cossack",
        "chair",
        "air",
        "clean",
        "snatch",
        "split",
    ):
        if token in title_norm and token not in name_norm:
            return f"forbidden variant '{token}'"

    return None


def title_matches_exercise(
    title: str,
    exercise_name: str,
    equipment: str | None = None,
) -> bool:
    if title_equipment_conflict(title, exercise_name, equipment):
        return False
    tokens = [t for t in title_tokens(exercise_name) if t not in EQUIPMENT_TOKENS]
    if not tokens:
        return True
    ratio = title_match_ratio(title, exercise_name)
    required = 1.0 if len(tokens) == 1 else 0.75
    return ratio + 1e-9 >= required


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


def build_targets(
    bundled: list[dict],
    limit: int | None,
    existing_mappings: list[dict] | None = None,
) -> list[ExerciseTarget]:
    """Prefer curated popularity names (including rep:local seed rows)."""
    popular_names = load_popular_exercise_names()
    existing_mappings = existing_mappings or []

    by_mapping_name: dict[str, list[dict]] = {}
    for mapping in existing_mappings:
        by_mapping_name.setdefault(norm(mapping["exerciseName"]), []).append(mapping)

    by_bundled_name = {norm(item["name"]): item for item in bundled}

    targets: list[ExerciseTarget] = []
    seen_ids: set[str] = set()

    def add_target(target: ExerciseTarget) -> None:
        if target.exercise_id in seen_ids:
            return
        seen_ids.add(target.exercise_id)
        targets.append(target)

    # 1) Walk popularity list first so --limit N hits the real top exercises.
    for popular_name in popular_names:
        key = norm(popular_name)
        mappings = by_mapping_name.get(key, [])
        if mappings:
            # Rematch every row sharing this display name (local seed + bundled).
            for mapping in mappings:
                add_target(
                    ExerciseTarget(
                        name=mapping["exerciseName"],
                        equipment=mapping.get("equipment") or "other",
                        exercise_id=mapping["exerciseId"],
                        bundled_catalog_id=mapping.get("bundledCatalogID"),
                    )
                )
            continue

        bundled_item = by_bundled_name.get(key)
        if bundled_item:
            add_target(
                ExerciseTarget(
                    name=bundled_item["name"],
                    equipment=bundled_item.get("equipment") or "other",
                    exercise_id=bundled_item["id"],
                    bundled_catalog_id=bundled_item["id"],
                )
            )

    # 2) Then remaining bundled exercises by popularity / name.
    ranked: list[tuple[int, str, ExerciseTarget]] = []
    for item in bundled:
        catalog_id = item["id"]
        if catalog_id in seen_ids:
            continue
        name = item["name"]
        ranked.append(
            (
                popularity_rank(name, popular_names),
                name.lower(),
                ExerciseTarget(
                    name=name,
                    equipment=item.get("equipment") or "other",
                    exercise_id=catalog_id,
                    bundled_catalog_id=catalog_id,
                ),
            )
        )
    ranked.sort(key=lambda row: (row[0], row[1]))
    for _, _, target in ranked:
        add_target(target)

    if limit is not None:
        keep_names: set[str] = set()
        for target in targets:
            key = norm(target.name)
            if key not in keep_names:
                if len(keep_names) >= limit:
                    break
                keep_names.add(key)
        targets = [target for target in targets if norm(target.name) in keep_names]

    return targets


def load_existing_mappings() -> list[dict]:
    if not OUTPUT.exists():
        return []
    payload = json.loads(OUTPUT.read_text())
    mappings = payload.get("mappings", [])
    return mappings if isinstance(mappings, list) else []


def mapping_keys(mappings: list[dict]) -> tuple[set[str], set[tuple[str, str]]]:
    done_ids: set[str] = set()
    done_keys: set[tuple[str, str]] = set()
    for mapping in mappings:
        done_ids.add(mapping["exerciseId"])
        bundled_id = mapping.get("bundledCatalogID")
        if isinstance(bundled_id, str) and bundled_id:
            done_ids.add(bundled_id)
        equipment = mapping.get("equipment") or "other"
        done_keys.add((norm(mapping["exerciseName"]), equipment))
    return done_ids, done_keys


class ProgressBar:
    def __init__(self, total: int, *, enabled: bool = True) -> None:
        self.total = max(total, 1)
        self.current = 0
        self.mapped = 0
        self.skipped = 0
        self.rejected = 0
        self.enabled = enabled
        # Carriage-return bar only works on a real terminal; elsewhere print one line per step.
        self.interactive = enabled and sys.stderr.isatty()
        self._status = ""
        self._started_at = time.monotonic()

    def set_counts(self, mapped: int, skipped: int, rejected: int) -> None:
        self.mapped = mapped
        self.skipped = skipped
        self.rejected = rejected

    def advance(
        self,
        current: int,
        status: str,
        *,
        mapped: int | None = None,
        skipped: int | None = None,
        rejected: int | None = None,
    ) -> None:
        self.current = current
        self._status = status
        if mapped is not None:
            self.mapped = mapped
        if skipped is not None:
            self.skipped = skipped
        if rejected is not None:
            self.rejected = rejected
        self._render()

    def _line(self) -> str:
        ratio = min(1.0, self.current / self.total)
        filled = int(PROGRESS_WIDTH * ratio)
        bar = "█" * filled + "░" * (PROGRESS_WIDTH - filled)
        elapsed = max(0.1, time.monotonic() - self._started_at)
        rate = self.current / elapsed
        remaining = max(0, self.total - self.current)
        eta_s = int(remaining / rate) if rate > 0 else 0
        eta = f"{eta_s // 60}m{eta_s % 60:02d}s" if eta_s >= 60 else f"{eta_s}s"
        counts = f"mapped {self.mapped} · skipped {self.skipped} · rejected {self.rejected}"
        return (
            f"{bar} {self.current}/{self.total} ({ratio * 100:5.1f}%) "
            f"ETA {eta} · {counts} · {self._status}"
        )

    def _render(self) -> None:
        if not self.enabled:
            return
        line = self._line()
        if self.interactive:
            sys.stderr.write(f"\r{line[:160]}")
            sys.stderr.flush()
        else:
            print(line[:160], flush=True)

    def note(self, message: str) -> None:
        if not self.enabled:
            print(message, flush=True)
            return
        if self.interactive:
            sys.stderr.write("\n")
            sys.stderr.flush()
        print(message, flush=True)

    def finish(self) -> None:
        if not self.enabled:
            return
        if self.interactive:
            self._render()
            sys.stderr.write("\n")
            sys.stderr.flush()
        else:
            self._render()


def write_catalog(
    mappings: list[dict],
    bundled_count: int,
    ascend_count: int,
    skipped: list[str],
    rejected: list[str],
    *,
    progress: ProgressBar | None = None,
) -> None:
    # Keep deterministic order: popularity was used for processing; sort by name for diffs.
    ordered = sorted(
        mappings,
        key=lambda row: (norm(row.get("exerciseName", "")), row.get("exerciseId", "")),
    )
    payload = {
        "schemaVersion": 1,
        "catalogVersion": time.strftime("%Y.%m.%d.1"),
        "publishedAt": time.strftime("%Y-%m-%dT00:00:00Z"),
        "bundledExerciseCount": bundled_count,
        "ascendApiExerciseCount": ascend_count or 1500,
        "mappings": ordered,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n")
    if progress is not None:
        progress.note(f"Wrote {len(ordered)} mappings to {OUTPUT}")
    else:
        print(f"\nWrote {len(ordered)} mappings to {OUTPUT}", flush=True)
    if skipped:
        summary = f"Skipped ({len(skipped)}): {', '.join(skipped[:20])}" + (
            " …" if len(skipped) > 20 else ""
        )
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


def ensure_ytdlp() -> None:
    if not Path(YTDLP).exists():
        raise RuntimeError(
            "yt-dlp is required. Install with: python3 -m pip install yt-dlp"
        )


def search_youtube(query: str) -> list[VideoCandidate]:
    ensure_ytdlp()
    try:
        out = subprocess.check_output(
            [
                YTDLP,
                f"ytsearch{SEARCH_RESULT_COUNT}:{query}",
                "--flat-playlist",
                "--dump-single-json",
                "--no-playlist",
                "--skip-download",
            ],
            text=True,
            timeout=60,
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
        duration = entry.get("duration")
        if isinstance(duration, float):
            duration = int(duration)
        if not isinstance(duration, int):
            duration = None
        upload_date = entry.get("upload_date")
        if not isinstance(upload_date, str) or not re.fullmatch(r"\d{8}", upload_date):
            upload_date = None
        view_count = entry.get("view_count")
        if isinstance(view_count, float):
            view_count = int(view_count)
        if not isinstance(view_count, int):
            view_count = None
        candidates.append(
            VideoCandidate(
                video_id=video_id,
                title=title,
                channel=channel,
                duration=duration,
                upload_date=upload_date,
                view_count=view_count,
            )
        )
    return candidates


def enrich_candidate(candidate: VideoCandidate) -> VideoCandidate:
    """Fill duration / upload_date when flat search omitted them."""
    if candidate.duration is not None and candidate.upload_date is not None:
        return candidate
    ensure_ytdlp()
    try:
        out = subprocess.check_output(
            [
                YTDLP,
                f"https://www.youtube.com/watch?v={candidate.video_id}",
                "--skip-download",
                "--dump-single-json",
                "--no-playlist",
            ],
            text=True,
            timeout=45,
            stderr=subprocess.DEVNULL,
        )
        meta = json.loads(out)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return candidate

    duration = meta.get("duration")
    if isinstance(duration, float):
        duration = int(duration)
    if not isinstance(duration, int):
        duration = candidate.duration

    upload_date = meta.get("upload_date")
    if not isinstance(upload_date, str) or not re.fullmatch(r"\d{8}", upload_date):
        upload_date = candidate.upload_date

    view_count = meta.get("view_count")
    if isinstance(view_count, float):
        view_count = int(view_count)
    if not isinstance(view_count, int):
        view_count = candidate.view_count

    title = meta.get("title") or candidate.title
    channel = meta.get("channel") or meta.get("uploader") or candidate.channel
    return VideoCandidate(
        video_id=candidate.video_id,
        title=title,
        channel=channel,
        duration=duration,
        upload_date=upload_date,
        view_count=view_count,
        score=candidate.score,
    )


def age_years(upload_date: str | None) -> float | None:
    if not upload_date:
        return None
    try:
        uploaded = datetime.strptime(upload_date, "%Y%m%d").replace(tzinfo=timezone.utc)
    except ValueError:
        return None
    now = datetime.now(timezone.utc)
    return max(0.0, (now - uploaded).days / 365.25)


def score_candidate(
    candidate: VideoCandidate,
    exercise_name: str,
    equipment: str | None = None,
) -> float:
    if title_rejected(candidate.title):
        return -1_000.0
    conflict = title_equipment_conflict(candidate.title, exercise_name, equipment)
    if conflict:
        return -1_000.0
    if not title_matches_exercise(candidate.title, exercise_name, equipment):
        return -1_000.0

    title_lower = candidate.title.lower()
    title_norm = norm(candidate.title)
    score = 0.0

    # Relevance
    score += 32.0 * title_match_ratio(candidate.title, exercise_name)
    # Exact-ish phrase boost
    if norm(exercise_name) in title_norm:
        score += 18.0
    if "barbell" in norm(equipment or "") or "barbell" in norm(exercise_name):
        if "barbell" in title_norm:
            score += 14.0
        if "back squat" in title_norm and "squat" in norm(exercise_name):
            score += 10.0

    # Helpful / short wording
    helpful_hits = sum(1 for pattern in HELPFUL_TITLE_PATTERNS if re.search(pattern, title_lower))
    score += min(22.0, helpful_hits * 7.0)
    if any(re.search(pattern, title_lower) for pattern in SHORT_HINT_PATTERNS):
        score += 6.0
    weak_hits = sum(1 for pattern in WEAK_TITLE_PATTERNS if re.search(pattern, title_lower))
    score -= weak_hits * 8.0

    # Duration — short, straight-to-form demos only
    duration = candidate.duration
    if duration is None:
        score -= 18.0
    elif duration < 8:
        score -= 30.0  # incomplete / spam
    elif duration <= 45:
        score += 48.0  # best: no room for a minute intro
    elif duration <= IDEAL_DURATION_MAX:
        score += 40.0
    elif duration <= SOFT_DURATION_MAX:
        score += 12.0
    elif duration <= HARD_DURATION_MAX:
        score -= 10.0
    else:
        return -1_000.0

    # Recency — modern videos first
    years = age_years(candidate.upload_date)
    if years is None:
        score -= 6.0
    elif years > MAX_AGE_YEARS:
        return -1_000.0
    elif years <= 1.5:
        score += 24.0
    elif years <= 3.0:
        score += 18.0
    elif years <= 5.0:
        score += 10.0
    else:
        score += 2.0

    # Trusted channel bonus (not exclusive)
    priority = channel_priority(candidate.channel)
    if priority is not None:
        score += max(0.0, 16.0 - priority * 0.7)

    # Light popularity signal — enough views to be real, not viral bait
    views = candidate.view_count
    if views is None:
        score -= 2.0
    elif views < 1_000:
        score -= 10.0
    elif views < 10_000:
        score += 2.0
    elif views < 2_000_000:
        score += 6.0
    else:
        score += 3.0

    # Prefer concise titles (less essay / listicle)
    word_count = len(candidate.title.split())
    if word_count <= 8:
        score += 3.0
    elif word_count >= 16:
        score -= 4.0

    return score


def search_queries(exercise_name: str, equipment: str) -> list[str]:
    name_norm = norm(exercise_name)
    equipment_norm = norm(equipment or "")
    negatives = "-smith -incline -decline -cossack -chair -wall -goblet -jump -pistol -clean"

    queries: list[str] = []
    if name_norm == "squat" and equipment_norm == "barbell":
        queries.extend(
            [
                f"barbell back squat proper form {negatives}",
                f"barbell squat proper form short {negatives}",
                f'"barbell squat" form tutorial {negatives}',
                f"barbell back squat form #shorts {negatives}",
                f"how to barbell squat demo {negatives}",
            ]
        )
    else:
        queries.extend(
            [
                f'"{exercise_name}" proper form {negatives}',
                f'"{exercise_name}" form tutorial {negatives}',
                f"{exercise_name} form #shorts {negatives}",
                f"{exercise_name} proper form short {negatives}",
                f"{exercise_name} how to demo {negatives}",
            ]
        )
        if "barbell" in name_norm or equipment_norm == "barbell":
            queries.append(f"barbell {exercise_name} form short {negatives}")
        if equipment and equipment_norm not in {"other", "none", "body only", "bodyweight"}:
            if equipment_norm not in name_norm:
                queries.append(f"{equipment} {exercise_name} form short {negatives}")

    seen: set[str] = set()
    ordered: list[str] = []
    for query in queries:
        key = norm(query)
        if key in seen:
            continue
        seen.add(key)
        ordered.append(query)
    return ordered


def pick_best_video(
    exercise_name: str,
    equipment: str,
    *,
    min_score: float,
) -> VideoCandidate | None:
    by_id: dict[str, VideoCandidate] = {}
    for query in search_queries(exercise_name, equipment):
        for candidate in search_youtube(query):
            existing = by_id.get(candidate.video_id)
            if existing is None:
                by_id[candidate.video_id] = candidate
                continue
            # Keep the entry with more metadata filled in
            if (existing.duration is None and candidate.duration is not None) or (
                existing.upload_date is None and candidate.upload_date is not None
            ):
                by_id[candidate.video_id] = candidate

    if not by_id:
        return None

    # Cheap pre-score with whatever flat-search gave us, then enrich the leaders.
    preliminary: list[VideoCandidate] = []
    for candidate in by_id.values():
        candidate.score = score_candidate(candidate, exercise_name, equipment)
        if candidate.score > -500:
            preliminary.append(candidate)
    preliminary.sort(key=lambda item: item.score, reverse=True)

    enriched: list[VideoCandidate] = []
    for candidate in preliminary[:ENRICH_TOP_N]:
        detailed = enrich_candidate(candidate)
        detailed.score = score_candidate(detailed, exercise_name, equipment)
        enriched.append(detailed)
        time.sleep(0.05)

    # Also keep non-enriched lower ranks so a great flat hit can still win.
    pool = {item.video_id: item for item in preliminary}
    for item in enriched:
        pool[item.video_id] = item

    ranked = sorted(pool.values(), key=lambda item: item.score, reverse=True)
    if not ranked:
        return None
    best = ranked[0]
    if best.score < min_score:
        return None
    return best


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
        default=0.2,
        help="Delay between exercise lookups",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Keep existing mappings and skip exercises already covered",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Re-search and overwrite existing mappings (implies not skipping them)",
    )
    parser.add_argument(
        "--checkpoint-every",
        type=int,
        default=5,
        help="Write the catalog every N newly mapped exercises",
    )
    parser.add_argument(
        "--min-score",
        type=float,
        default=MIN_ACCEPT_SCORE,
        help="Minimum score required to accept a candidate",
    )
    parser.add_argument(
        "--no-progress",
        action="store_true",
        help="Disable the live progress bar",
    )
    args = parser.parse_args()
    min_score = args.min_score

    ascend = json.loads(ASCEND_CACHE.read_text()) if ASCEND_CACHE.exists() else []
    bundled = json.loads(BUNDLED_CATALOG.read_text())["exercises"]
    existing = load_existing_mappings() if (args.resume or args.replace or args.limit) else []
    targets = build_targets(bundled, args.limit, existing_mappings=existing)

    if args.replace:
        target_ids = {target.exercise_id for target in targets}
        mappings = [
            mapping
            for mapping in existing
            if mapping.get("exerciseId") not in target_ids
        ]
    elif args.resume:
        mappings = list(existing)
    else:
        # Keep untouched catalog rows when only rematching a limited popular set.
        if args.limit is not None and existing:
            target_ids = {target.exercise_id for target in targets}
            mappings = [
                mapping
                for mapping in existing
                if mapping.get("exerciseId") not in target_ids
            ]
        else:
            mappings = []

    done_ids, done_keys = mapping_keys(mappings)
    skipped: list[str] = []
    rejected: list[str] = []
    new_since_checkpoint = 0

    # Group by display name so sibling IDs (rep:local + free-exercise-db) share one search.
    groups: list[list[ExerciseTarget]] = []
    group_index: dict[str, int] = {}
    for target in targets:
        key = norm(target.name)
        if key in group_index:
            groups[group_index[key]].append(target)
        else:
            group_index[key] = len(groups)
            groups.append([target])

    total = len(groups)
    progress = ProgressBar(total, enabled=not args.no_progress)
    progress.set_counts(len(mappings), 0, 0)

    for index, group in enumerate(groups, start=1):
        target = group[0]
        key = (norm(target.name), target.equipment)
        if not args.replace and all(
            member.exercise_id in done_ids or key in done_keys for member in group
        ):
            progress.advance(index, f"resume {target.name[:24]}")
            continue

        candidate = pick_best_video(
            target.name,
            target.equipment,
            min_score=min_score,
        )
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

        candidate.title = meta["title"]
        candidate.channel = meta["channel"]
        candidate.score = score_candidate(
            candidate, target.name, target.equipment
        )
        if candidate.score < min_score:
            rejected.append(
                f"{target.name}:{candidate.video_id}:score={candidate.score:.1f}"
            )
            progress.advance(
                index,
                f"low score {target.name[:24]}",
                mapped=len(mappings),
                skipped=len(skipped),
                rejected=len(rejected),
            )
            continue

        group_ids = {member.exercise_id for member in group}
        mappings = [
            mapping
            for mapping in mappings
            if mapping.get("exerciseId") not in group_ids
        ]
        for member in group:
            entry = {
                "exerciseId": member.exercise_id,
                "bundledCatalogID": member.bundled_catalog_id,
                "exerciseName": member.name,
                "equipment": member.equipment,
                "youtubeVideoId": candidate.video_id,
                "title": meta["title"],
                "channel": meta["channel"],
                "verifiedAt": time.strftime("%Y-%m-%d"),
            }
            mappings.append(entry)
            done_ids.add(member.exercise_id)
        done_keys.add(key)
        new_since_checkpoint += 1
        duration_note = (
            f"{candidate.duration}s" if candidate.duration is not None else "?s"
        )
        progress.advance(
            index,
            f"✓ {target.name[:18]} · {duration_note} · {meta['channel'][:12]} · {candidate.score:.0f}",
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
