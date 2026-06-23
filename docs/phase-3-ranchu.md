# Phase 3 Ranchu Runtime and App Windows

Status: **host and guest implementation landed; the strict stock-AVD proof
passed on June 23, 2026; Community Runtime image execution remains**.

## Runtime choice

Greenhouse now targets the open-source Android Emulator engine and its ARM64
Goldfish/Ranchu guest hardware:

```text
Apple Silicon
  → Android Emulator
  → Hypervisor.framework (HVF) CPU acceleration
  → gfxstream host GPU transport
  → Metal/OpenGL translation and MoltenVK on macOS
  → ARM64 LineageOS SDK phone system image
```

This replaces the Cuttlefish product target. Greenhouse does not use
Virtualization.framework scanouts for Android app presentation.

The Community Runtime inherits
`vendor/lineage/build/target/product/lineage_sdk_phone_arm64.mk`, includes the
Ranchu graphics/HAL stack, keeps system partitions immutable, and stores
userdata in the managed AVD directory.

## Independent app-window path

`GreenhouseAppWindowAgent` is a platform-signed system extension app. For each
host window it:

1. creates a trusted, own-content virtual display;
2. creates a surface-input H.264 `MediaCodec` encoder;
3. attaches the encoder surface to that display;
4. launches the selected package with `ActivityOptions.setLaunchDisplayId`;
5. sends codec configuration and frames through a length-prefixed local socket;
6. injects pointer, keyboard, committed IME text, and controller events with
   the display ID;
7. captures PCM output through an Android audio-policy mix restricted to the
   launched app's UID;
8. resizes or releases the display without stopping the shared Android system.

The socket is `localabstract:greenhouse-app-window`. The host reaches it only
through a localhost ADB forward created by Greenhouse's private ADB server.

On macOS, `GreenhouseRuntime`:

- starts the AVD with `-accel on -gpu host`;
- owns an isolated ADB server and key/data home;
- requires boot completion, package manager, accelerated graphics, and the
  app-window agent before reporting readiness;
- requires `vkjson` to expose an active non-software Vulkan device rather than
  trusting the guest feature declaration alone;
- decodes H.264 with VideoToolbox;
- renders decoded pixel buffers into an `MTKView`;
- routes focus, backing-scale resize, pointer, keyboard/IME text, and
  GameController state to the matching stream/display;
- plays display-session PCM audio with AVAudioEngine;
- synchronizes host and guest monotonic clocks with ping/pong samples and
  reports control RTT plus p95 VideoToolbox decode and Metal presentation
  latency in each live app window.

Set `GREENHOUSE_BACKEND=ranchu` to select this backend in development. The fake
backend remains the default until a runtime is provisioned.

For a built Community Runtime, point Greenhouse directly at the copied emulator
images:

```bash
GREENHOUSE_BACKEND=ranchu \
GREENHOUSE_SYSTEM_IMAGE_DIR="$PWD/artifacts/community-runtime/images" \
  ./script/build_and_run.sh
```

The immutable `userdata.img` in that directory is used only as the initial
template. Writable data lives separately under Greenhouse's managed runtime
data directory and survives engine restarts.

## Stock ARM64 AVD proof

Install Android command-line tools, Emulator, platform tools, the Android 35
Google APIs ARM64 system image, scrcpy 4.0 or newer, and ffmpeg. Create the
stock proof AVD:

```bash
avdmanager create avd \
  -n greenhouse_stock \
  -k "system-images;android-35;google_apis;arm64-v8a" \
  -d pixel_7 \
  --force
```

After reviewing and accepting Google's Android SDK license terms, run:

```bash
./script/prove_stock_runtime.sh
```

Set `GREENHOUSE_AVD_NAME` or `GREENHOUSE_AVD_HOME` if the AVD uses a different
name or location.

The proof launches two stock apps on two scrcpy-created virtual displays,
collects GLES/Vulkan and codec data, records both streams for frame timestamp
analysis, measures targeted-input command RTT, verifies both tasks are assigned
to distinct display IDs, asserts a flex-display resize and display teardown,
restarts the AVD, verifies a userdata marker, and writes:

```text
artifacts/phase3/stock-avd/report.json
```

The stock harness reports targeted ADB input-command round trip as a control
measurement. Native Greenhouse sessions separately report synchronized control
RTT plus decode, Metal presentation, and audio transport latency; neither value
is mislabeled as glass-to-glass latency.

### Measured stock result

The strict proof passed on an Apple M5 using Android Emulator 36.6.11,
Android 15 Google APIs ARM64, scrcpy 4.0, and the `greenhouse_stock` AVD:

| Measurement | Result |
| --- | --- |
| CPU acceleration | HVF |
| Cold boot to Android ready | 12.42 s |
| GLES renderer | Android Emulator OpenGL ES Translator on Apple M5 |
| GLES version | OpenGL ES 3.0 |
| Vulkan device/driver | Apple M5 / MoltenVK |
| Vulkan feature version | `4206592` (Vulkan 1.3 declaration) |
| Independent displays | IDs 2 and 3 |
| App task routing | Settings → 2; Files → 3 |
| Display startup | 704 ms; 782 ms |
| ADB targeted-input command RTT | 47.54 ms mean; 69.25 ms p95 |
| Active-swipe frame samples | 137; 175 |
| Mean encoded frame rate | 22.83 FPS; 7.41 FPS |
| p95 frame interval | 100 ms for both streams |
| Native-window resize | Passed for both displays |
| Display teardown | Passed |
| Userdata restart persistence | Passed |

These stock apps are not a graphics benchmark. Their event-driven rendering
produced substantial idle gaps even under alternating swipe input, especially
in Files. The measurements prove two accelerated encoded display paths and
expose their current pacing; a representative game and native Greenhouse
VideoToolbox path remain the performance acceptance workload.

The Community Runtime transport can be exercised headlessly after a Linux
build:

```bash
./script/prove_community_runtime.sh
```

It checks the microG/F-Droid package set, private ADB, the guest-agent health
handshake, two simultaneous decoded display streams, synchronized latency
metrics, and restart persistence.

The 50-cycle lifecycle/persistence gate is separate so it can run unattended:

```bash
./script/soak_runtime.sh
```

It defaults to 50 cold start/stop cycles and fails immediately if Android does
not become ready or the guest marker disappears. Set
`GREENHOUSE_SYSTEM_IMAGE_DIR` to run the same soak against built Community
Runtime images rather than the stock AVD.

The stock AVD completed all 50 cycles on June 23, 2026:

| Lifecycle measurement | Result |
| --- | --- |
| Cycles passed | 50 / 50 |
| Persistence checks passed | 50 / 50 |
| Mean cold-boot time | 12.65 s |
| Maximum cold-boot time | 13.76 s |

## Remaining execution gates

- Build `greenhouse_sdk_phone_arm64-userdebug` on Linux. The app-window agent
  already compiles against pinned Android 16 QPR2 AOSP test/platform stubs, but
  the full Soong build remains required.
- Exercise two Community Runtime sessions through Greenhouse's native Metal
  windows and record end-to-end latency.
- Run the lifecycle soak against the built Community Runtime and complete the
  representative app/game compatibility set.
