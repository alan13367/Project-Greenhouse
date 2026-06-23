# Project Greenhouse

<p align="center">
  <img src="apps/GreenhouseMac/Resources/AppIcon-1024.png" alt="Project Greenhouse app icon" width="192">
</p>

Project Greenhouse is building the easiest way to run Android apps on an Apple
Silicon Mac. The product runs one managed Android environment in the background
and presents each Android app in its own Mac window.

> Current status: the Phase 3 host and guest implementation is in-tree. The
> strict stock ARM64 AVD proof and a 50-cycle persistence soak passed on
> June 23, 2026. The remaining acceptance gate is building the pinned
> LineageOS Community Runtime on Linux and running the same two-window proof
> through Greenhouse's native VideoToolbox/Metal path.

## Build, test, and run

Requirements:

- Apple Silicon Mac
- macOS 15.0 or later
- A current full Xcode installation

Run:

```bash
./script/test.sh
./script/build_and_run.sh
```

`test.sh` builds the Swift package, runs all tests, compiles the Android guest
agent against pinned platform stubs, validates runtime metadata, and checks the
Ranchu/app-window source contract.

`build_and_run.sh` is the main interactive command. It builds a SwiftPM
executable, stages a local
`dist/GreenhouseMac.app`, and launches it as a normal foreground Mac app. It
uses the deterministic fake backend unless `GREENHOUSE_BACKEND=ranchu` is set,
and supports `--verify`, `--debug`, `--logs`, and `--telemetry`.

## What Phase 1 proves

- Backend-neutral runtime, VM, Android, Google-service, operation, and app-window
  state models.
- A deterministic fake backend covering the happy path and all roadmap failure
  cases.
- A SwiftUI app library, microG and F-Droid entry points, package picker, runtime
  progress, diagnostics, and independent fake app windows.
- Versioned NDJSON development events with unified logging and redaction.
- Unit and integration tests plus repeatable local verification.

## Phase 2 decision

Virtualization.framework and generic QEMU/HVF were rejected because their
tested macOS graphics paths did not provide the accelerated, independent
Android surfaces Greenhouse needs. The decision is preserved in
[ADR 0002](docs/adr/0002-platform-feasibility-no-go.md) and the
[backend decision](docs/backend-decision.md); the disposable probe code is not
part of the product repository.

## What Phase 3 implements

- ARM64 Goldfish/Ranchu instead of Cuttlefish.
- Android Emulator engine launch with HVF and `-gpu host`
  gfxstream/MoltenVK acceleration.
- One trusted Android virtual display and MediaCodec stream per app.
- VideoToolbox decoding into native Metal-backed Mac windows.
- Display-scoped resize, focus, pointer, keyboard/IME text, audio, and
  controller routing.
- Isolated localhost ADB and persistent managed AVD userdata.
- A reproducible two-app stock-AVD proof, JSON measurement report, and
  50-cycle lifecycle/persistence soak.

See [the Phase 3 Ranchu design and execution gate](docs/phase-3-ranchu.md).

## Product boundaries

The v1 contract targets macOS 15.0+ on Apple Silicon and ARM64 or universal
Android apps. x86 Android apps, Intel Macs, every Android hardware feature, and
universal compatibility with DRM, anti-cheat, or Play Integrity enforcement are
not promised.

The v1 Community Runtime uses microG-compatible services, F-Droid, and local
packages. It does not include official Google Play or proprietary GMS. Licensed
Google Play support remains a possible future distribution track.

Read the [product contract](docs/product-contract.md) and
[Community Runtime design](docs/community-runtime.md) before
making compatibility or distribution claims.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). 
Greenhouse host code is licensed under Apache 2.0.
