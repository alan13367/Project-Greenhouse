# Development

## Requirements

- Apple Silicon Mac.
- macOS 15.0 or later.
- Full Xcode with the macOS SDK. Command Line Tools alone are not sufficient for
  this SwiftUI app.

## Commands

```bash
./scripts/dev-bootstrap.sh
./scripts/build-and-test.sh
./script/build_and_run.sh
```

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

The Codex desktop Run action is configured in
`.codex/environments/environment.toml`.

## App icon

The editable source artwork is `assets/Project Greenhouse Icon.png`. Regenerate
the transparent 1024 px master and all macOS `.icns` representations with:

```bash
./scripts/generate-app-icon.sh
```

This requires ImageMagick. The script removes only the edge-connected black
surround, trims the visible artwork, applies consistent transparent padding,
and writes the bundle resources under `apps/GreenhouseMac/Resources/`.

## Project layout

- `GreenhouseCore`: domain models, backend contract, fake backend, events,
  redaction, and app model.
- `GreenhouseMac`: SwiftUI scenes and feature views.
- `GreenhouseCoreTests`: unit and integration tests.

Keep backend-specific vocabulary below the protocol. Add a typed issue and a
deterministic fake scenario before wiring a new user-visible failure.
