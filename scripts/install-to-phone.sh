#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM="${DEVELOPMENT_TEAM:-P84T7RYX7T}"
XCODE_DEVICE="${XCODE_DEVICE_ID:-00008130-001054E421C0001C}"
DEVCTL_DEVICE="${DEVCTL_DEVICE_ID:-DCEB444A-743B-5F44-8B6E-7603C67DD50A}"
BUNDLE_ID="${BUNDLE_ID:-com.example.Rep}"
DD="${DERIVED_DATA_PATH:-.build/DerivedData}"
APP="$DD/Build/Products/Debug-iphoneos/Rep.app"

LAUNCH=1
BUILD_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --no-launch) LAUNCH=0 ;;
    --build-only) BUILD_ONLY=1; LAUNCH=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-launch] [--build-only]"
      exit 0
      ;;
  esac
done

echo "→ Building for Sindres iPhone…"
xcodebuild build \
  -project Rep.xcodeproj \
  -scheme Rep \
  -destination "id=$XCODE_DEVICE" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  -quiet

if [[ "$BUILD_ONLY" -eq 1 ]]; then
  echo "✓ Built: $APP"
  exit 0
fi

echo "→ Installing…"
xcrun devicectl device install app --device "$DEVCTL_DEVICE" "$APP"

if [[ "$LAUNCH" -eq 1 ]]; then
  echo "→ Launching…"
  xcrun devicectl device process launch --device "$DEVCTL_DEVICE" "$BUNDLE_ID"
fi

echo "✓ Rep is on your phone."
