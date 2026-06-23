# ADR 0004: Adopt the Android Emulator Engine and Ranchu

- Status: Accepted for Phase 3 implementation
- Date: 2026-06-23

## Context

The Phase 2 Virtualization.framework and generic QEMU probes could boot ARM64
Linux but could not provide both accelerated Android graphics and independent
app surfaces. Greenhouse must not depend on a single VM scanout.

The Android Emulator engine already defines an ARM64 Goldfish/Ranchu guest
contract, HVF acceleration on Apple Silicon, gfxstream host rendering, and
MoltenVK-backed Vulkan on macOS. Android can separately render trusted virtual
displays into MediaCodec surfaces.

## Decision

- Build the Community Runtime from LineageOS's
  `lineage_sdk_phone_arm64` product.
- Launch it with the Android Emulator engine, HVF, and host GPU mode.
- Do not use Virtualization.framework scanouts for Android app presentation.
- Create one trusted Android virtual display per app.
- Export each display as a low-latency MediaCodec stream.
- Decode H.264 with VideoToolbox and present it in a Metal-backed Mac window.
- Keep ADB on an isolated localhost server and reach the guest agent through a
  localabstract socket forward.
- Keep immutable system images separate from persistent AVD userdata.

## Consequences

The first implementation depends on Android Emulator redistribution and
packaging work rather than only system frameworks. The stream adds codec
latency, which must be measured and optimized. In return, Greenhouse gains the
Android-specific graphics stack and avoids coupling native app windows to
emulator scanout count.

The Phase 2 no-go remains accurate for its tested backends; this ADR selects a
different Android-specialized engine path.
