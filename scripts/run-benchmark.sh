#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$ROOT/tools/realesrgan"

if [[ -x "$TOOLS/realesrgan-ncnn-vulkan" ]]; then
  export PATH="$TOOLS:$PATH"
  export REALESRGAN_BIN="$TOOLS/realesrgan-ncnn-vulkan"
  export REALESRGAN_MODEL="${REALESRGAN_MODEL:-4x-UltraSharp-fp16}"
fi

exec python3 "$ROOT/benchmark-exercise-media.py" "$@"
