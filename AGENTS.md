# Greenhouse

This is the repository for **Project Greenhouse**, the easiest way for everyday users to run Android apps and games on Apple Silicon Macs.

The goal is not to build a traditional emulator UI. The goal is to make Android apps feel like Mac apps:

```text
Open Greenhouse → Install from Google Play or an APK → Open the app or game in its own Mac window
```

Users should not have to understand Android versions, virtual machines, ADB, system images, ABIs, RAM, CPU cores, QEMU, HVF, or Android build tooling.

Greenhouse runs one managed Android system in the background and presents Android apps through a native-feeling Mac experience.

The Android runtime is infrastructure, not the product. Most people should
never see an emulator window, an ADB prompt, or a setup screen full of machine
settings. Runtime preparation, persistence, recovery, and updates should feel
like ordinary parts of the Mac app.

Each Android app should have its own identity and window on macOS. Opening,
focusing, resizing, closing, and reopening one app should not disturb the
others or restart the shared Android system. Keyboard, trackpad, controller,
audio, clipboard, and files should follow the window the user is actually
interacting with.

Prefer product-shaped abstractions over leaking backend mechanics upward. The
UI should talk about preparing Android, opening an app, or recovering from a
problem—not launching an AVD, forwarding an ADB port, or creating a virtual
display. Keep those details below the backend boundary and turn failures into
clear, actionable product states.

## Testing the work

The normal confidence check is:

```bash
./script/test.sh
```

This is the command that should pass before changes are considered ready. It
builds and tests the Mac code, validates the Community Runtime metadata,
compiles the guest app-window agent against the pinned Android APIs, and checks
the important Ranchu and per-app-window assumptions in the source tree.

For changes that affect the actual app experience, also run:

```bash
./script/build_and_run.sh
```

The default fake backend is intentional. It is the fast, deterministic way to
exercise preparation, startup, installation, failures, and multiple independent
Mac windows without requiring an Android image. New user-visible states and
failures should generally be representable there before they are wired to the
real runtime.

Runtime work needs stronger evidence than a successful build. Use
`./script/prove_stock_runtime.sh` when changing emulator, graphics, display,
streaming, resize, input, or persistence behavior. Use
`./script/soak_runtime.sh` for lifecycle changes. The Community Runtime proof is
`./script/prove_community_runtime.sh` and requires images built on Linux.

Generated images, recordings, downloaded packages, SDK stubs, and measurement
reports belong under ignored `artifacts/`; they are evidence, not source.
Durable conclusions belong in the relevant design document or ADR. Avoid
keeping one-off probe scripts after the question they answered has been
settled.

Testing should follow the product promise. A feature is not proven merely
because Android reports that it exists: open real apps, use two windows at
once, resize them, move focus between them, send input to the correct display,
restart the runtime, and verify that user data survives. Measure latency and
frame pacing where they matter, and describe precisely what was measured
rather than turning a development signal into a compatibility claim.
