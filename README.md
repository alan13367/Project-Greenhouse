# Project Greenhouse

<p align="center">
  <img src="apps/GreenhouseMac/Resources/AppIcon-1024.png" alt="Project Greenhouse app icon" width="192">
</p>

Project Greenhouse is building the easiest way to run Android apps on an Apple
Silicon Mac. The product runs one managed Android environment in the background
and presents each Android app in its own Mac window.

> Current status: Phase 0 and Phase 1 foundation. The repository contains a
> native SwiftUI shell and deterministic fake backend. It does **not** yet
> contain an Android runtime, virtualization backend, Google Play, or Google
> proprietary software.

## Foundation demo

Requirements:

- Apple Silicon Mac
- macOS 15.0 or later
- A current full Xcode installation

Run:

```bash
./scripts/dev-bootstrap.sh
./script/build_and_run.sh
```

Inside Greenhouse:

1. Choose **Prepare Android**.
2. Choose **Start Android**.
3. Add the two demo apps.
4. Open both apps to create independent Mac windows.
5. Open **Advanced Diagnostics** and exercise any failure scenario.

The run script builds a SwiftPM executable, stages a local
`dist/GreenhouseMac.app`, and launches it as a normal foreground Mac app. It
also supports `--verify`, `--debug`, `--logs`, and `--telemetry`.

## What Phase 1 proves

- Backend-neutral runtime, VM, Android, Google-service, operation, and app-window
  state models.
- A deterministic fake backend covering the happy path and all roadmap failure
  cases.
- A SwiftUI app library, Google Play entry point, package picker, runtime
  progress, diagnostics, and independent fake app windows.
- Versioned NDJSON development events with unified logging and redaction.
- Unit and integration tests plus macOS CI.

## Product boundaries

The v1 contract targets macOS 15.0+ on Apple Silicon and ARM64 or universal
Android apps. x86 Android apps, Intel Macs, every Android hardware feature, and
universal compatibility with DRM, anti-cheat, or Play Integrity enforcement are
not promised.

Google Play is a release requirement and an unresolved release blocker. GMS is
not part of AOSP and will only be distributed after an explicit license and
certification path with Google. No proprietary Google binaries belong in this
repository.

Read the [product contract](docs/product-contract.md) and
and [Google Play feasibility assessment](docs/google-play-feasibility.md) before
making compatibility or distribution claims.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). 
Greenhouse host code is licensed under Apache 2.0.
