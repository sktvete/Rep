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
WAIT_SECONDS="${DEVICE_WAIT_SECONDS:-45}"

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

device_ready() {
  local json
  json="$(mktemp)"
  if ! xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1; then
    rm -f "$json"
    return 1
  fi
  python3 - "$json" "$DEVCTL_DEVICE" "$XCODE_DEVICE" <<'PY'
import json, sys
path, core_id, udid = sys.argv[1:4]
data = json.load(open(path))
for device in data.get("result", {}).get("devices", []):
    ids = {device.get("identifier"), device.get("hardwareProperties", {}).get("udid")}
    if core_id not in ids and udid not in ids:
        continue
    conn = device.get("connectionProperties", {})
    props = device.get("deviceProperties", {})
    tunnel = conn.get("tunnelState")
    ddi = props.get("ddiServicesAvailable")
    # ready when developer services are up (info details often wakes the tunnel)
    sys.exit(0 if ddi and tunnel in {"connected", "connecting"} else 1)
sys.exit(1)
PY
  local status=$?
  rm -f "$json"
  return "$status"
}

wake_device() {
  # Listing as "available (paired)" is not enough — wireless needs a tunnel.
  xcrun devicectl device info details --device "$DEVCTL_DEVICE" >/dev/null 2>&1 \
    || xcrun devicectl device info details --device "$XCODE_DEVICE" >/dev/null 2>&1 \
    || true
}

echo "→ Waiting for Sindres iPhone developer tunnel…"
deadline=$((SECONDS + WAIT_SECONDS))
until device_ready; do
  wake_device
  if (( SECONDS >= deadline )); then
    echo "✗ Phone paired but developer tunnel never connected." >&2
    echo "  Unlock the phone, keep it awake, prefer USB, then retry." >&2
    xcrun devicectl list devices >&2 || true
    exit 1
  fi
  sleep 1
done
echo "✓ Device ready"

echo "→ Building for Sindres iPhone…"
if ! xcodebuild build \
  -project Rep.xcodeproj \
  -scheme Rep \
  -destination "platform=iOS,id=$XCODE_DEVICE" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" \
  -quiet
then
  echo "→ Device destination failed; building generic iOS…"
  xcodebuild build \
    -project Rep.xcodeproj \
    -scheme Rep \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DD" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" \
    -quiet
fi

if [[ "$BUILD_ONLY" -eq 1 ]]; then
  echo "✓ Built: $APP"
  exit 0
fi

if [[ ! -d "$APP" ]]; then
  echo "✗ Missing app bundle: $APP" >&2
  exit 1
fi

echo "→ Installing…"
wake_device
if ! xcrun devicectl device install app --device "$DEVCTL_DEVICE" "$APP"; then
  echo "→ Retrying install with hardware UDID…"
  xcrun devicectl device install app --device "$XCODE_DEVICE" "$APP"
fi

if [[ "$LAUNCH" -eq 1 ]]; then
  echo "→ Launching…"
  if ! xcrun devicectl device process launch --device "$DEVCTL_DEVICE" "$BUNDLE_ID"; then
    xcrun devicectl device process launch --device "$XCODE_DEVICE" "$BUNDLE_ID"
  fi
fi

echo "✓ Rep is on your phone."
