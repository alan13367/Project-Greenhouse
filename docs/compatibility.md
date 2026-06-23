# Compatibility Contract

Compatibility is reported per app and per Greenhouse runtime version. “Android
boots” is not a compatibility result.

## Initial categories

| Category | v1 position | Evidence required |
| --- | --- | --- |
| Pure Java/Kotlin APK | Targeted | Install, launch, window, input, network, audio, resume |
| ARM64 native APK | Targeted | Above plus native library load and crash-free run |
| Universal APK | Targeted when it contains ARM64 | Selected ABI and install record |
| Split APK set | Targeted | Complete split validation and atomic install |
| x86/x86_64-only APK | Unsupported | Clear pre-install rejection |
| 2D app | Targeted | Resize, DPI, text input, clipboard, focus |
| 3D game | Measured subset | Graphics API, frame pacing, controller, audio |
| App with no Google API dependency | Targeted | Core flows pass with Google compatibility disabled |
| App compatible with microG | Measured subset | Required account, push, location, maps, or related flows pass |
| App requiring official GMS/Play Store | Unsupported in Community Runtime | Dependency and failed core flow recorded |
| Play Integrity / DRM / anti-cheat app | Best effort only | Actual verdict and app behavior; no bypasses |
| Phone-hardware-dependent app | Conditional | Required-feature inventory and graceful degradation |

## Result vocabulary

- **Works:** tested core flows succeed without a known material defect.
- **Works with limitations:** usable, with named missing or degraded behavior.
- **Does not work:** install, launch, rendering, input, or a core flow fails.
- **Blocked by policy:** a licensing, integrity, DRM, or anti-cheat decision
  rejects the environment.
- **Not tested:** no claim.

Every result records the app version, source, runtime build, macOS version, Mac
model, backend, graphics path, input devices, tested flows, and known issues.
Results belong under `compatibility/results/`; copyrighted app or game assets do
not.

Every result also records the Google-service provider (`none`, `microG`, or
`licensedGMS`). A result obtained with microG must never be presented as an
official Google Play compatibility result.
