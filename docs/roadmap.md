# Greenhouse Roadmap

Greenhouse runs one managed Android system and presents each Android app in its
own native-feeling Mac window. Users should never need to understand AVDs,
system images, ADB, QEMU, or Android build tooling.

## Product contract

- Apple Silicon and macOS 15 or later.
- ARM64 or universal Android applications.
- One persistent managed Android runtime.
- One independently resizable Mac window per Android task.
- Native keyboard, pointer, IME, audio, and controller routing.
- A Community Runtime with microG-compatible services, F-Droid, and local APKs.
- Official Google Play only through a future licensed distribution track.

## Completed foundations

### Phase 0 — contract and constraints

The product, security, compatibility, licensing, and distribution boundaries
are documented.

### Phase 1 — native product shell

The SwiftUI app, backend-neutral domain model, deterministic fake backend,
typed diagnostics, independent fake app windows, event logging, and tests are
implemented.

### Phase 2 — backend feasibility

Virtualization.framework and generic QEMU/HVF were tested and rejected for the
production Android path. They could boot ARM64 guests, but the tested macOS
graphics stacks did not provide accelerated GLES/Vulkan plus independent
surfaces. The durable conclusion lives in ADR 0002; disposable probes were
removed.

## Phase 3 — Ranchu runtime and native app windows

Selected architecture:

```text
Greenhouse Mac app
  → open-source Android Emulator engine
  → HVF CPU acceleration
  → ARM64 Goldfish/Ranchu guest
  → gfxstream and MoltenVK host GPU path
  → trusted Android virtual display per app
  → MediaCodec H.264 transport
  → VideoToolbox decode
  → Metal-backed Mac window
```

Implemented:

- Ranchu runtime lifecycle and persistent userdata.
- Isolated localhost ADB server and managed keys.
- Guest readiness and accelerated GLES/Vulkan checks.
- Platform guest agent with trusted virtual displays and display-targeted task
  launch.
- Per-display video, resize, focus, keyboard, pointer, IME, audio, and
  controller protocol.
- VideoToolbox decoding and Metal presentation.
- Stock ARM64 AVD proof with two simultaneous app displays.
- 50/50 cold-start and persistence soak.
- Pinned LineageOS 23.2 Community Runtime product, microG/F-Droid supply lock,
  and reproducible Linux build tooling.

Measured stock proof on June 23, 2026:

- Android Emulator 36.6.11 on Apple M5 with HVF.
- GLES 3.0 through the Android Emulator translator.
- Vulkan device Apple M5 through MoltenVK.
- Independent display IDs 2 and 3 with correct task routing.
- 12.42-second cold boot.
- Resize, teardown, input, and userdata persistence passed.
- 50/50 lifecycle cycles passed; 12.65-second mean cold boot.

Remaining Phase 3 acceptance work:

1. Build `greenhouse_sdk_phone_arm64-userdebug` on a Linux host with at least
   300 GiB available.
2. Run two Community Runtime apps through Greenhouse's native
   VideoToolbox/Metal windows.
3. Record synchronized control, decode, presentation, frame-pacing, resize,
   audio, controller, lifecycle, and persistence measurements.
4. Exercise a representative 3D game and the compatibility test set.

Phase 3 is complete only when those Community Runtime results pass and are
recorded.

## Later phases

### Phase 4 — installation and library

Make APK installation, F-Droid discovery, app metadata, icons, updates,
uninstall, storage, and launch behavior safe for everyday users.

### Phase 5 — native polish

Finish window restoration, menus, drag and drop, clipboard, file integration,
notifications, accessibility, display scaling, controller UX, and recovery
flows.

### Phase 6 — distribution

Complete dependency notices, signing, notarization, update delivery, clean-Mac
installation, runtime acquisition, rollback, and support diagnostics.

### Phase 7 — compatibility and release

Publish tested app/game results, performance and thermal limits, known
incompatibilities, privacy behavior, and precise claims for the first release.

## Canonical developer commands

```bash
./script/test.sh
./script/build_and_run.sh
```

Runtime proof commands are documented in `docs/development.md` and are not part
of the everyday edit/build/run loop.
