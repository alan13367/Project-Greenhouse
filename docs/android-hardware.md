# Android Hardware Spike

Status: ARM64 Goldfish/Ranchu selected and wired into the Community Runtime;
the stock ARM64 AVD proof passed and custom-image execution remains.

## Selected baseline

Greenhouse uses the Android Emulator's ARM64 SDK-phone product and Ranchu
virtual hardware. The engine runs on Apple Silicon with HVF CPU acceleration.
Its host GPU mode uses gfxstream and can use MoltenVK for accelerated Vulkan on
macOS. This is the same virtual-hardware family used by stock ARM64 AVDs and
does not depend on a Virtualization.framework framebuffer.

References:

- <https://developer.android.com/studio/run/emulator-acceleration>
- <https://developer.android.com/studio/run/emulator-commandline>
- <https://android.googlesource.com/platform/device/generic/goldfish/>

## Proposed virtual hardware

| Area | Required Android-facing device |
| --- | --- |
| CPU | ARM64, four or more virtual CPUs |
| Memory | Configurable ARM64 RAM with ballooning optional |
| Boot | Direct kernel/initramfs during experiments; verified boot for product builds |
| System storage | Read-only system partitions plus separate persistent userdata |
| Network | Android Emulator network behind host NAT |
| Private control | Isolated localhost ADB server plus localabstract guest-agent socket |
| Display | One trusted Android virtual display and encoded stream per app |
| Graphics | Ranchu/gfxstream guest stack with host GPU mode and MoltenVK |
| Input | Keyboard, absolute pointer, relative pointer, touch semantics, controller |
| Audio | Low-latency PCM output and later microphone input if declared |
| Entropy | Virtio entropy |
| File import | Explicit host broker; no home-directory mount |

The rejected Phase 2 Linux probes remain useful evidence about
Virtualization.framework and generic QEMU, but neither is the selected Android
graphics or app-window path.

## Android integration consequences

Android supports multiple secondary displays and can launch user tasks on
trusted system-managed displays. It also requires display-aware input routing.
A privileged Greenhouse guest component is therefore required to:

- create or own trusted app displays;
- launch selected activities on a target display;
- observe task and activity changes;
- route virtual input devices to the correct display;
- handle permissions, dialogs, secondary activities, IME, and orientation;
- keep background services alive when host windows close.

References:

- <https://source.android.com/docs/core/display/multi_display>
- <https://source.android.com/docs/core/display/multi_display/activity-launch>
- <https://source.android.com/docs/core/display/multi_display/input-routing>

## CTS plan

Once the Ranchu Community Runtime boots:

1. Retain the exact LineageOS revision-locked manifest and security patch level.
2. Define the declared device type and optional hardware features with Google.
3. Build a production-equivalent user image.
4. Run the latest matching ARM64 CTS on every candidate build.
5. Run all applicable CTS Verifier display, audio, input, connectivity, and
   media cases.
6. Track stable failures by build, backend, and hardware profile.

No Android image or proprietary Google component is committed to Git.
