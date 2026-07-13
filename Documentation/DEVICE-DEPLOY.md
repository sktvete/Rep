# Push Rep to your iPhone (fast)

One command from the repo root:

```sh
./scripts/install-to-phone.sh
```

Build, install, and launch on **Sindres iPhone**. Typical time: ~15–25s after the first run (incremental builds are faster).

## Prerequisites (once)

1. iPhone unlocked, plugged in via USB (or on the same network with wireless debugging enabled).
2. **Settings → Privacy & Security → Developer Mode** enabled on the phone.
3. Xcode signed in: **Xcode → Settings → Accounts** with your Apple ID.
4. First install only: **Settings → General → VPN & Device Management** → trust your developer certificate.

Check the phone is visible:

```sh
xcrun devicectl list devices
```

You want `Sindres iPhone` in state `available (paired)`.

## What the script does

1. Builds `Debug-iphoneos` with your team id and automatic provisioning.
2. Installs `Rep.app` via `devicectl`.
3. Launches `com.example.Rep`.

## Manual one-liner

If you prefer not to use the script:

```sh
TEAM=P84T7RYX7T
DEVICE=00008130-001054E421C0001C
DEVCTL=DCEB444A-743B-5F44-8B6E-7603C67DD50A
DD=.build/DerivedData

xcodebuild build \
  -project Rep.xcodeproj \
  -scheme Rep \
  -destination "id=$DEVICE" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  -quiet

xcrun devicectl device install app \
  --device "$DEVCTL" \
  "$DD/Build/Products/Debug-iphoneos/Rep.app"

xcrun devicectl device process launch \
  --device "$DEVCTL" \
  com.example.Rep
```

## Speed tips

- **Incremental builds**: the script uses a stable `.build/DerivedData` path so Xcode reuses compiled objects.
- **Skip launch**: `./scripts/install-to-phone.sh --no-launch`
- **Build only** (no install): `./scripts/install-to-phone.sh --build-only`
- **Quiet failures**: if install fails, run `xcrun devicectl list devices` — the phone is usually unplugged, locked, or needs Developer Mode.
- **From Xcode**: select **Sindres iPhone** as the run destination and press **⌘R** (slower to start, same result).

## Device / team ids (this machine)

| Key | Value |
|-----|-------|
| Development team | `P84T7RYX7T` |
| xcodebuild device id | `00008130-001054E421C0001C` |
| devicectl device id | `DCEB444A-743B-5F44-8B6E-7603C67DD50A` |
| Bundle id | `com.example.Rep` |

If you get a new phone or Apple ID, update `scripts/install-to-phone.sh` and this table.

## Troubleshooting

| Error | Fix |
|-------|-----|
| `No Account for Team` | Sign into Xcode → Settings → Accounts |
| `No profiles for com.example.Rep` | Add `-allowProvisioningUpdates` (script already does); ensure phone is connected |
| `device not found` | Unlock phone, replug USB, confirm with `devicectl list devices` |
| App won't open | Trust developer cert in Settings → General → VPN & Device Management |
