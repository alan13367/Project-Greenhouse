# Graphics and Game Feasibility

Status: **Phase 2 gate failed; Phase 3 Ranchu stock proof passed; Community
Runtime and representative-game measurements remain**.

## Phase 3 selection

Greenhouse no longer attempts to obtain Android game graphics from a
Virtualization.framework scanout or a generic Homebrew QEMU display backend.
It launches the open-source Android Emulator engine with an ARM64 Ranchu guest,
HVF, and `-gpu host`. The selected Android guest includes gfxstream and the
Ranchu Vulkan stack; host Vulkan translation on macOS is provided through
MoltenVK.

Per-app windows do not consume emulator scanouts. Android renders each trusted
virtual display into a MediaCodec surface. The host decodes that H.264 stream
with VideoToolbox and presents the resulting pixel buffers through Metal.

`script/prove_stock_runtime.sh` records the reported GLES renderer, Vulkan
properties, MediaCodec inventory, frame-rate samples, and resize evidence.

The June 23, 2026 stock proof selected Apple M5 through MoltenVK, reported
OpenGL ES 3.0 translation, exposed two trusted virtual displays, and passed
task routing, resize, teardown, and persistence. Event-driven Settings and
Files workloads measured 22.83 and 7.41 mean encoded FPS with 100 ms p95 frame
intervals. Those values characterize the stock-app workload and are not a game
performance claim.

## Virtualization.framework

The ARM64 Linux guest initializes the public Virtio GPU and a framebuffer. Its
DRM report is decisive:

```text
features: -virgl -resource_blob -host_visible
number of scanouts: 1
number of cap sets: 0
```

The public Linux graphics configuration exposes no host renderer selection,
VirGL capability, resource-blob path, or Vulkan Venus path. This is a working
2D display, not the accelerated game architecture Greenhouse needs.

## QEMU/HVF

QEMU 11.0.1 with HVF boots the same ARM64 Linux kernel and exposes two 2D
scanouts. The installed redistributable build has:

- no `virtio-gpu-gl`/VirGL device;
- no OpenGL-capable SDL or GTK display backend;
- no Venus Vulkan renderer;
- zero guest GPU capability sets.

QEMU's hardware flexibility therefore helps multi-display exploration but does
not currently provide the required accelerated macOS graphics path.

## Benchmark decision

The rejected Phase 2 backends have no meaningful accelerated frame-rate result.
The selected Ranchu path now has stock-app pacing evidence and a verified
non-software Vulkan device. A representative 3D game remains required before a
game-performance acceptance decision.

The next graphics candidate must demonstrate:

- accelerated OpenGL ES;
- Vulkan 1.1 or higher if Greenhouse declares a non-low-RAM 64-bit handheld
  Android 17 profile;
- stable frame pacing and shader compilation;
- controller and relative-pointer latency;
- synchronized low-latency audio;
- sustained thermal behavior.

References:

- <https://developer.android.com/studio/run/emulator-acceleration>
- <https://android.googlesource.com/platform/device/generic/goldfish/>
