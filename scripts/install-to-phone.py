#!/usr/bin/env python3
"""Build Rep for device, install on Sindres iPhone, and launch."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEAM = os.environ.get("DEVELOPMENT_TEAM", "P84T7RYX7T")
XCODE_DEVICE = os.environ.get("XCODE_DEVICE_ID", "00008130-001054E421C0001C")
DEVCTL_DEVICE = os.environ.get("DEVCTL_DEVICE_ID", "DCEB444A-743B-5F44-8B6E-7603C67DD50A")
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.example.Rep")
DERIVED_DATA = Path(os.environ.get("DERIVED_DATA_PATH", ROOT / ".build" / "DerivedData"))
APP = DERIVED_DATA / "Build" / "Products" / "Debug-iphoneos" / "Rep.app"


def run(cmd: list[str], *, quiet: bool = False) -> None:
    kwargs: dict = {"cwd": ROOT, "check": True}
    if quiet:
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    subprocess.run(cmd, **kwargs)


def build() -> None:
    print("→ Building for Sindres iPhone…")
    run(
        [
            "xcodebuild",
            "build",
            "-project",
            "Rep.xcodeproj",
            "-scheme",
            "Rep",
            "-destination",
            f"id={XCODE_DEVICE}",
            "-derivedDataPath",
            str(DERIVED_DATA),
            "-allowProvisioningUpdates",
            f"DEVELOPMENT_TEAM={TEAM}",
            "-quiet",
        ],
    )


def install() -> None:
    print("→ Installing…")
    run(
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
    )


def launch() -> None:
    print("→ Launching…")
    run(
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
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-launch", action="store_true", help="Install without launching.")
    parser.add_argument("--build-only", action="store_true", help="Build only; do not install.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    build()
    if args.build_only:
        print(f"✓ Built: {APP}")
        return
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
