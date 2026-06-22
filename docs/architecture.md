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

The backend protocol owns preparation, lifecycle, package installation, Google
Play entry, app open/close, simulation, and an asynchronous event stream. It
does not expose QEMU arguments, VZ objects, ADB commands, or raw process errors.

State is split into runtime installation, VM lifecycle, Android readiness,
Google services, current operation, and per-app window state. A single event may
patch several related machines, but no combined mega-enum hides valid
combinations.

The fake backend is the executable specification for deterministic transitions:

```text
runtime missing → downloading → verifying → installing → ready
VM stopped → starting → running → stopping → stopped
Android unavailable → booting → connecting → ready
app closed → creating display → launching task → visible
```

Future backend experiments conform to the same contract. Backend-specific
configuration belongs under `experiments/backends/`, while accepted product
code belongs in `Backends/`.
