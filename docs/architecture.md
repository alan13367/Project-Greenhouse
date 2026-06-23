# Foundation Architecture

Phase 1 deliberately separates product state from backend mechanics.

```text
SwiftUI scenes
├── App library and runtime preparation
├── Value-keyed fake Android app windows
├── Settings
└── Advanced diagnostics
        ↓
GreenhouseAppModel
├── independent domain state machines
├── app catalog and task/window state
├── typed user-facing issues
└── redacted event journal
        ↓
GreenhouseBackend protocol
        ↓
FakeBackend (Phase 1)
```

The backend protocol owns preparation, lifecycle, package installation,
Google-compatibility setup, community-store entry, app open/close, simulation,
and an asynchronous event stream. It
does not expose QEMU arguments, VZ objects, ADB commands, or raw process errors.

State is split into runtime installation, VM lifecycle, Android readiness,
Google-service provider and readiness, current operation, and per-app window
state. A single event may
patch several related machines, but no combined mega-enum hides valid
combinations.

The fake backend is the executable specification for deterministic transitions:

```text
runtime missing → downloading → verifying → installing → ready
VM stopped → starting → running → stopping → stopped
Android unavailable → booting → connecting → ready
app closed → creating display → launching task → visible
```

Phase 2 rejected Virtualization.framework and generic QEMU/HVF because their
tested macOS graphics paths did not provide accelerated independent Android
surfaces. The durable decision remains in ADR 0002; the disposable probe code
was removed.

Phase 3 selects an ARM64 Goldfish/Ranchu guest running through the Android
Emulator engine. `GreenhouseRuntime` owns HVF/host-GPU launch, isolated ADB,
readiness, app streams, VideoToolbox, Metal, audio, and input routing.
`GreenhouseAppWindowAgent` owns trusted virtual displays, targeted task launch,
MediaCodec encoding, and display-scoped event injection inside Android.

The fake backend remains the deterministic product specification. Set
`GREENHOUSE_BACKEND=ranchu` to run the real backend after provisioning an AVD.
