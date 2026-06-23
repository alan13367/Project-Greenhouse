# Per-App Window Feasibility

Status: **the stock dual-display proof passed; Community Runtime execution
through Greenhouse's native windows remains**.

Android's trusted-display and targeted-launch primitives are now owned by the
platform-signed `GreenhouseAppWindowAgent`. Each display renders into its own
MediaCodec input surface and is exported independently over a private local
socket. This avoids depending on physical or virtual GPU scanout count.

## Virtualization.framework result

The probe attaches a `VZVirtualMachineView`, boots a Linux Virtio GPU, and
receives a working framebuffer. The macOS 27 SDK states that
`VZVirtioGraphicsDeviceConfiguration` supports a maximum of one scanout. The
guest independently reports one scanout.

One scanout cannot represent two independently resized Android app displays.
Showing the same scanout in two views would duplicate one framebuffer, not
produce two task surfaces.

## QEMU/HVF result

QEMU 11 can configure two Virtio GPU scanouts, and the guest reports both.
That is promising hardware flexibility, but it is not the roadmap proof:

- no Android tasks were launched;
- scanouts were not exported as separate native Mac windows;
- independent focus, resize, orientation, and close/reopen were not tested;
- the graphics path remained unaccelerated.

QEMU therefore does not pass the per-app window gate.

## Implemented path

For each app:

1. create a trusted own-content virtual display;
2. attach a surface-input H.264 encoder;
3. launch the package with `ActivityOptions.setLaunchDisplayId`;
4. decode frames with VideoToolbox into an `MTKView`;
5. resize the display when the Mac window backing size changes;
6. tag input events with the Android display ID;
7. close the display while leaving the shared Android system running.

The host registry supports simultaneous sessions and gives every app its own
ADB forward, stream ID, decoder, audio player, and native Mac window.

## Remaining Community Runtime proof

The final acceptance run must show one persistent Community Runtime with:

1. two real Android activities on distinct trusted displays;
2. one native Mac window per surface;
3. correct keyboard, pointer, IME, and focus ownership;
4. independent resize and orientation;
5. close/reopen without stopping Android;
6. background services surviving with no app windows visible.

Android references:

- <https://source.android.com/docs/core/display/multi_display>
- <https://source.android.com/docs/core/display/multi_display/displays>
- <https://source.android.com/docs/core/display/multi_display/input-routing>
