# Community Runtime

Status: Phase 3 Ranchu integration implemented June 23, 2026; Linux image build
and runtime execution remain.

Greenhouse now has an open-source Google-compatibility path that does not
redistribute proprietary GMS:

```text
LineageOS 23.2 / Android 16 QPR2
  + restricted system-only signature spoofing
  + microG Services Core
  + microG Services Framework Proxy
  + microG Companion/FakeStore
  + F-Droid and its privileged extension
```

This provides a credible compatibility layer for many applications that call
Google service APIs. It does not provide official Google Play, Google
certification, guaranteed Play Integrity verdicts, Google Play billing, or
universal app compatibility.

## Reproducible inputs

`guest/community-runtime/runtime-lock.json` pins:

- the LineageOS manifest branch and bootstrap commit;
- the `android_vendor_partner_gms` integration commit;
- every downloaded APK version, URL, destination, license, and SHA-256.

`script/fetch_community_runtime.sh` downloads each package to the ignored
`artifacts/` directory, verifies its digest, checks out the integration commit,
and stages the Greenhouse product definition. No APK is committed to Git.

The Linux build writes `repo manifest -r` after synchronization. That generated
manifest is the exact multi-repository commit set and must be retained with any
candidate runtime artifact.

## Build

Small-package verification works on macOS or Linux:

```bash
script/fetch_community_runtime.sh
script/verify_community_runtime.sh --downloads
```

The full Android build requires a Linux worktree with at least 300 GiB free:

```bash
script/build_community_runtime.sh /path/to/lineage-worktree
```

The build target is:

```text
greenhouse_sdk_phone_arm64-userdebug
```

The product inherits LineageOS's ARM64 SDK-phone target for the Android
Emulator's Goldfish/Ranchu hardware. It includes the platform-signed
`GreenhouseAppWindowAgent`, Ranchu graphics/HAL stack, microG, F-Droid, and a
separate persistent userdata image. See `docs/phase-3-ranchu.md`.

## Promotion gates

A generated image is not a releasable runtime until all of these pass:

1. The image boots on the selected Greenhouse backend.
2. The recorded Android security patch level meets the release policy.
3. microG self-check passes with restricted signature spoofing.
4. F-Droid can refresh repositories and install an app.
5. A test app completes the required Google-compatible account, push,
   location, and mapping flows relevant to that app.
6. Integrity-, DRM-, billing-, and anti-cheat-dependent apps are reported
   honestly rather than bypassed.
7. Licenses, corresponding source, notices, signing, updates, rollback, and
   clean-Mac distribution are complete.
