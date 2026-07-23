#!/usr/bin/env python3
"""Build a local HTML reviewer for exercise help videos and open it."""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Rep/Resources/Catalog/exercise-help-videos-v1.json"
POPULARITY_SOURCE = ROOT / "Rep/Shared/ExercisePopularity.swift"
DEFAULT_OUT = ROOT / ".build/help-video-review.html"


def load_popular_names() -> list[str]:
    source = POPULARITY_SOURCE.read_text()
    match = re.search(
        r"private static let orderedNames: \[String\] = \[(.*?)\]",
        source,
        re.DOTALL,
    )
    if not match:
        raise RuntimeError(f"Could not parse orderedNames from {POPULARITY_SOURCE}")
    return re.findall(r'"([^"]+)"', match.group(1))


def norm(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", " ", value.lower())
    return " ".join(cleaned.split())


def select_mappings(mappings: list[dict], limit: int) -> list[dict]:
    popular = load_popular_names()
    by_name = {norm(m["exerciseName"]): m for m in mappings}
    selected: list[dict] = []
    seen: set[str] = set()
    for name in popular:
        mapping = by_name.get(norm(name))
        if not mapping:
            continue
        key = mapping["exerciseId"]
        if key in seen:
            continue
        seen.add(key)
        selected.append(mapping)
        if len(selected) >= limit:
            break
    return selected


def render_html(mappings: list[dict]) -> str:
    cards: list[str] = []
    for index, mapping in enumerate(mappings, start=1):
        video_id = html.escape(mapping["youtubeVideoId"])
        exercise = html.escape(mapping["exerciseName"])
        title = html.escape(mapping["title"])
        channel = html.escape(mapping["channel"])
        thumb = f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
        cards.append(
            f"""
            <article class="card" data-video-id="{video_id}">
              <button class="thumb" type="button" aria-label="Play {exercise}">
                <img src="{thumb}" alt="" loading="lazy" />
                <span class="play">▶</span>
              </button>
              <div class="meta">
                <div class="rank">{index}</div>
                <h2>{exercise}</h2>
                <p class="title">{title}</p>
                <p class="channel">{channel}</p>
                <a href="https://www.youtube.com/watch?v={video_id}" target="_blank" rel="noreferrer">Open on YouTube</a>
              </div>
              <div class="player" hidden></div>
            </article>
            """
        )

    body = "\n".join(cards)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Rep help video review</title>
  <style>
    :root {{
      --bg: #0f1115;
      --card: #171a21;
      --text: #f3f5f7;
      --muted: #9aa3ad;
      --line: #2a3140;
      --accent: #5b8cff;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: "SF Pro Text", "Helvetica Neue", sans-serif;
      background: radial-gradient(1200px 600px at 20% -10%, #1a2440, transparent),
                  radial-gradient(900px 500px at 100% 0%, #1c1828, transparent),
                  var(--bg);
      color: var(--text);
      min-height: 100vh;
    }}
    header {{
      position: sticky;
      top: 0;
      z-index: 2;
      backdrop-filter: blur(12px);
      background: rgba(15, 17, 21, 0.85);
      border-bottom: 1px solid var(--line);
      padding: 16px 20px;
    }}
    header h1 {{
      margin: 0 0 4px;
      font-size: 20px;
      font-weight: 650;
    }}
    header p {{
      margin: 0;
      color: var(--muted);
      font-size: 13px;
    }}
    main {{
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
      gap: 16px;
      padding: 20px;
      max-width: 1400px;
      margin: 0 auto;
    }}
    .card {{
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 16px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }}
    .thumb {{
      position: relative;
      display: block;
      width: 100%;
      aspect-ratio: 16 / 9;
      padding: 0;
      border: 0;
      cursor: pointer;
      background: #000;
    }}
    .thumb img {{
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }}
    .play {{
      position: absolute;
      inset: 0;
      margin: auto;
      width: 56px;
      height: 56px;
      border-radius: 999px;
      display: grid;
      place-items: center;
      background: rgba(0,0,0,0.55);
      color: white;
      font-size: 22px;
      border: 1px solid rgba(255,255,255,0.25);
    }}
    .thumb:hover .play {{ background: rgba(91,140,255,0.85); }}
    .meta {{
      padding: 14px 14px 16px;
      display: grid;
      gap: 6px;
    }}
    .rank {{
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.04em;
    }}
    h2 {{
      margin: 0;
      font-size: 17px;
      line-height: 1.25;
    }}
    .title {{
      margin: 0;
      color: var(--text);
      font-size: 14px;
      line-height: 1.35;
    }}
    .channel {{
      margin: 0;
      color: var(--muted);
      font-size: 13px;
    }}
    a {{
      color: var(--accent);
      font-size: 13px;
      text-decoration: none;
      width: fit-content;
    }}
    a:hover {{ text-decoration: underline; }}
    .player {{
      aspect-ratio: 16 / 9;
      background: #000;
    }}
    .player iframe {{
      width: 100%;
      height: 100%;
      border: 0;
      display: block;
    }}
    .card.playing .thumb {{ display: none; }}
    .card.playing .player {{ display: block; }}
  </style>
</head>
<body>
  <header>
    <h1>Rep help video review</h1>
    <p>{len(mappings)} videos · click a thumbnail to play · titles are YouTube titles</p>
  </header>
  <main>
    {body}
  </main>
  <script>
    document.querySelectorAll('.card').forEach((card) => {{
      const button = card.querySelector('.thumb');
      const player = card.querySelector('.player');
      const videoId = card.dataset.videoId;
      button.addEventListener('click', () => {{
        document.querySelectorAll('.card.playing').forEach((other) => {{
          if (other === card) return;
          other.classList.remove('playing');
          other.querySelector('.player').hidden = true;
          other.querySelector('.player').innerHTML = '';
        }});
        card.classList.add('playing');
        player.hidden = false;
        player.innerHTML =
          '<iframe src="https://www.youtube.com/embed/' + videoId +
          '?autoplay=1&rel=0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>';
      }});
    }});
  </script>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args()

    payload = json.loads(args.catalog.read_text())
    selected = select_mappings(payload.get("mappings", []), args.limit)
    if not selected:
        raise SystemExit("No mappings selected for review.")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render_html(selected))
    print(f"Wrote {args.out} ({len(selected)} videos)")
    for index, mapping in enumerate(selected, start=1):
        print(f"{index:2d}. {mapping['exerciseName']} — {mapping['title']} [{mapping['channel']}]")

    if not args.no_open:
        url = args.out.resolve().as_uri()
        opened = webbrowser.open(url)
        if not opened:
            subprocess.run(["open", str(args.out.resolve())], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
