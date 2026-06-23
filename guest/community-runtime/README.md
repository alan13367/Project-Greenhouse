# Greenhouse Community Runtime

This directory defines the Phase 3 Android guest target:

- LineageOS 23.2 / Android 16 QPR2 / ARM64.
- LineageOS ARM64 SDK phone on the Android Emulator's Goldfish/Ranchu virtual
  hardware.
- HVF CPU acceleration with gfxstream host GPU translation and MoltenVK for
  Vulkan on macOS.
- A platform-signed app-window agent that creates one trusted virtual display
  and MediaCodec stream per launched app.
- microG with restricted, system-only signature spoofing.
- F-Droid and user-provided Android packages.
- No official Google Play Store or proprietary GMS binaries.

`runtime-lock.json` pins the bootstrap manifest revision, microG integration
revision, APK versions, URLs, and SHA-256 hashes. The Linux build writes a
fully revision-locked `repo manifest -r` file beside its output; that generated
manifest is required when promoting a runtime build for distribution.

Prepare and build on a dedicated Linux filesystem with at least 300 GiB free:

```bash
script/build_community_runtime.sh /path/to/lineage-worktree
```

To download and verify only the small community packages on macOS or Linux:

```bash
script/fetch_community_runtime.sh
script/verify_community_runtime.sh --downloads
```

The resulting guest is a compatibility-oriented community build. microG can
support many apps that use Google APIs, but it is not Google certification,
Google Play, or a promise that Play Integrity, DRM, anti-cheat, billing, or
every push/location API will work.

The product emits an emulator system-image target and keeps userdata separate
from immutable system partitions. Greenhouse launches that image through the
open-source Android Emulator engine; it does not consume a
Virtualization.framework scanout.
