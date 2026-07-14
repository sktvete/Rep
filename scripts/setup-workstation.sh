#!/usr/bin/env bash
# One-time setup for GPU exercise-media benchmarking on Linux (RTX 3080).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$ROOT/tools/realesrgan"
MODELS="$TOOLS/models"
REALESRGAN_VERSION="20220424"
REALESRGAN_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-${REALESRGAN_VERSION}-ubuntu.zip"
ULTRASHARP_BIN="https://huggingface.co/Kim2091/UltraSharp/resolve/main/NCNN/4x-UltraSharp-fp16.bin"
ULTRASHARP_PARAM="https://huggingface.co/Kim2091/UltraSharp/resolve/main/NCNN/4x-UltraSharp-fp16.param"

echo "→ Installing Python deps…"
python3 -m pip install --user -r "$ROOT/requirements-media.txt"

mkdir -p "$MODELS"
if [[ ! -x "$TOOLS/realesrgan-ncnn-vulkan" ]]; then
  echo "→ Downloading realesrgan-ncnn-vulkan…"
  tmp="$(mktemp -d)"
  curl -fsSL "$REALESRGAN_URL" -o "$tmp/realesrgan.zip"
  unzip -qo "$tmp/realesrgan.zip" -d "$tmp"
  mkdir -p "$TOOLS"
  cp -R "$tmp"/realesrgan-ncnn-vulkan-*/. "$TOOLS/"
  rm -rf "$tmp"
fi

if [[ ! -f "$MODELS/4x-UltraSharp-fp16.bin" ]]; then
  echo "→ Downloading 4x-UltraSharp (NCNN fp16)…"
  curl -fsSL "$ULTRASHARP_BIN" -o "$MODELS/4x-UltraSharp-fp16.bin"
  curl -fsSL "$ULTRASHARP_PARAM" -o "$MODELS/4x-UltraSharp-fp16.param"
fi

cat <<EOF

Done.

Run a single benchmark:
  export PATH="$TOOLS:\$PATH"
  export REALESRGAN_MODEL=4x-UltraSharp-fp16
  "$ROOT/run-benchmark.sh" --manifest /path/to/licensed-media.json --slug example --download --rights-confirmed

Run a licensed manifest:
  "$ROOT/run-benchmark.sh" --manifest /path/to/licensed-media.json --download --rights-confirmed

Outputs (gitignored):
  scripts/exercise-media/benchmark/output/
EOF
