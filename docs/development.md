# Development

## Requirements

- Apple Silicon Mac.
- macOS 15.0 or later.
- Full Xcode with the macOS SDK. Command Line Tools alone are not sufficient for
  this SwiftUI app.

## Commands

The everyday development loop has two commands:

```bash
./script/test.sh
./script/build_and_run.sh
```

`test.sh` is the canonical non-interactive check. It builds and tests the Mac
package, verifies Community Runtime metadata, compiles the Android guest agent
against pinned platform stubs, validates JSON and shell sources, and checks the
Ranchu/app-window implementation contract.

`build_and_run.sh` is the canonical interactive check. It builds, bundles, and
launches Greenhouse. The deterministic fake backend is the default, so this
command does not require an Android image.

The run script automatically uses `/Applications/Xcode.app` or
`/Applications/Xcode-beta.app` when `xcode-select` points at standalone Command
Line Tools. Set `DEVELOPER_DIR` explicitly to override that choice.

Run modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

Community Runtime package verification:

```bash
./script/fetch_community_runtime.sh
./script/verify_community_runtime.sh --downloads
```

Reproduce the stock Ranchu acceptance proof after installing Android Emulator,
platform tools, the Android 35 Google APIs ARM64 image, scrcpy 4.0+, ffmpeg,
and an AVD named `greenhouse_stock`:

```bash
./script/prove_stock_runtime.sh
./script/soak_runtime.sh
```

Override `GREENHOUSE_AVD_NAME` or `GREENHOUSE_AVD_HOME` for a differently named
AVD. The proof uses a private ADB server and writes measurements beneath the
ignored `artifacts/` directory. It does not replace the normal build and test
command.

Run the native backend against a built Community Runtime:

```bash
GREENHOUSE_BACKEND=ranchu \
GREENHOUSE_SYSTEM_IMAGE_DIR="$PWD/artifacts/community-runtime/images" \
  ./script/build_and_run.sh

./script/prove_community_runtime.sh
```

The full LineageOS build is Linux-only and requires at least 300 GiB free:

```bash
./script/build_community_runtime.sh /path/to/dedicated-lineage-worktree
```

The Codex desktop Run action is configured in
`.codex/environments/environment.toml`.

## App icon

The editable source artwork is `assets/Project Greenhouse Icon.png`. Regenerate
the transparent 1024 px master and all macOS `.icns` representations with:

```bash
./script/generate_app_icon.sh
```

This requires ImageMagick. The script removes only the edge-connected black
surround, trims the visible artwork, applies consistent transparent padding,
and writes the bundle resources under `apps/GreenhouseMac/Resources/`.

## Project layout

- `GreenhouseCore`: domain models, backend contract, fake backend, events,
  redaction, and app model.
- `GreenhouseRuntime`: Android Emulator/HVF lifecycle, private ADB, app stream
  protocol, VideoToolbox/Metal presentation, audio, and input routing.
- `GreenhouseMac`: SwiftUI scenes and feature views.
- `GreenhouseCoreTests`: unit and integration tests.
- `guest/community-runtime`: pinned Android product and package lock.
- `guest/app-window-agent`: platform-signed trusted-display and MediaCodec
  service built into the Community Runtime.
- `script`: developer commands, runtime acceptance tools, and repository
  maintenance utilities.

Keep backend-specific vocabulary below the protocol. Add a typed issue and a
deterministic fake scenario before wiring a new user-visible failure.
