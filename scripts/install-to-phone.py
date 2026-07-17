#!/usr/bin/env python3
"""Build Rep for device, install on Sindres iPhone, and launch."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEAM = os.environ.get("DEVELOPMENT_TEAM", "P84T7RYX7T")
XCODE_DEVICE = os.environ.get("XCODE_DEVICE_ID", "00008130-001054E421C0001C")
DEVCTL_DEVICE = os.environ.get("DEVCTL_DEVICE_ID", "DCEB444A-743B-5F44-8B6E-7603C67DD50A")
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.example.Rep")
DERIVED_DATA = Path(os.environ.get("DERIVED_DATA_PATH", ROOT / ".build" / "DerivedData"))
APP = DERIVED_DATA / "Build" / "Products" / "Debug-iphoneos" / "Rep.app"
WAIT_SECONDS = int(os.environ.get("DEVICE_WAIT_SECONDS", "45"))


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, check=check, text=True)


def wake_device() -> None:
    for device in (DEVCTL_DEVICE, XCODE_DEVICE):
        result = run(
            ["xcrun", "devicectl", "device", "info", "details", "--device", device],
            check=False,
        )
        if result.returncode == 0:
            return


def device_ready() -> bool:
    with tempfile.NamedTemporaryFile(suffix=".json") as handle:
        result = run(
            ["xcrun", "devicectl", "list", "devices", "--json-output", handle.name],
            check=False,
        )
        if result.returncode != 0:
            return False
        data = json.loads(Path(handle.name).read_text())
    for device in data.get("result", {}).get("devices", []):
        ids = {
            device.get("identifier"),
            device.get("hardwareProperties", {}).get("udid"),
        }
        if DEVCTL_DEVICE not in ids and XCODE_DEVICE not in ids:
            continue
        conn = device.get("connectionProperties", {})
        props = device.get("deviceProperties", {})
        tunnel = conn.get("tunnelState")
        ddi = props.get("ddiServicesAvailable")
        return bool(ddi and tunnel in {"connected", "connecting"})
    return False


def wait_for_device() -> None:
    print("→ Waiting for Sindres iPhone developer tunnel…")
    deadline = time.time() + WAIT_SECONDS
    while True:
        if device_ready():
            print("✓ Device ready")
            return
        wake_device()
        if time.time() >= deadline:
            print("✗ Phone paired but developer tunnel never connected.", file=sys.stderr)
            print("  Unlock the phone, keep it awake, prefer USB, then retry.", file=sys.stderr)
            run(["xcrun", "devicectl", "list", "devices"], check=False)
            raise SystemExit(1)
        time.sleep(1)


def build() -> None:
    print("→ Building for Sindres iPhone…")
    primary = run(
        [
            "xcodebuild",
            "build",
            "-project",
            "Rep.xcodeproj",
            "-scheme",
            "Rep",
            "-destination",
            f"platform=iOS,id={XCODE_DEVICE}",
            "-derivedDataPath",
            str(DERIVED_DATA),
            "-allowProvisioningUpdates",
            "-allowProvisioningDeviceRegistration",
            f"DEVELOPMENT_TEAM={TEAM}",
            "-quiet",
        ],
        check=False,
    )
    if primary.returncode == 0:
        return
    print("→ Device destination failed; building generic iOS…")
    run(
        [
            "xcodebuild",
            "build",
            "-project",
            "Rep.xcodeproj",
            "-scheme",
            "Rep",
            "-destination",
            "generic/platform=iOS",
            "-derivedDataPath",
            str(DERIVED_DATA),
            "-allowProvisioningUpdates",
            "-allowProvisioningDeviceRegistration",
            f"DEVELOPMENT_TEAM={TEAM}",
            "-quiet",
        ],
    )


def install() -> None:
    print("→ Installing…")
    wake_device()
    primary = run(
        [
            "xcrun",
            "devicectl",
            "device",
            "install",
            "app",
            "--device",
            DEVCTL_DEVICE,
            str(APP),
        ],
        check=False,
    )
    if primary.returncode == 0:
        return
    print("→ Retrying install with hardware UDID…")
    run(
        [
            "xcrun",
            "devicectl",
            "device",
            "install",
            "app",
            "--device",
            XCODE_DEVICE,
            str(APP),
        ],
    )


def launch() -> None:
    print("→ Launching…")
    primary = run(
        [
            "xcrun",
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            DEVCTL_DEVICE,
            BUNDLE_ID,
        ],
        check=False,
    )
    if primary.returncode == 0:
        return
    run(
        [
            "xcrun",
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            XCODE_DEVICE,
            BUNDLE_ID,
        ],
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-launch", action="store_true", help="Install without launching.")
    parser.add_argument("--build-only", action="store_true", help="Build only; do not install.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    wait_for_device()
    build()
    if args.build_only:
        print(f"✓ Built: {APP}")
        return
    if not APP.is_dir():
        print(f"✗ Missing app bundle: {APP}", file=sys.stderr)
        raise SystemExit(1)
    install()
    if not args.no_launch:
        launch()
    print("✓ Rep is on your phone.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(f"✗ Command failed (exit {error.returncode})", file=sys.stderr)
        raise SystemExit(error.returncode)
