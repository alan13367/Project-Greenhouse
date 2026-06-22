# Product Contract

Status: accepted for v1 planning on June 23, 2026.

## Promise

Project Greenhouse lets everyday Mac users install and run Android apps and
games, including apps from Google Play when an authorized distribution path is
secured, through native-feeling Mac windows.

The normal flow is:

```text
Open Greenhouse → Install from Google Play or a package → Open the app
```

Users manage apps, not virtual machines. Backend names, ADB, Android images,
ABIs, and resource tuning stay in Advanced Diagnostics.

## Supported v1 envelope

- Apple Silicon Macs running macOS 15.0 or later.
- One persistent, Greenhouse-managed Android system.
- A separate Mac window for each supported foreground Android app or game.
- ARM64 Android applications and pure Java/Kotlin applications.
- User-provided universal APKs and supported split APK sets.
- Keyboard, mouse, trackpad, audio, networking, and game controllers.
- Accelerated graphics for a measured compatibility set.
- Google Play and Google Play services only through a written Google license
  and the applicable compatibility/certification process.
- Direct-download distribution using Developer ID signing and notarization.

## Explicit non-goals

- Intel Mac support.
- x86 or x86_64 Android application translation.
- Compatibility with every app, game, DRM system, anti-cheat system, or
  app-specific security policy.
- Guaranteed favorable Play Integrity verdicts.
- Every phone sensor, cellular feature, camera mode, NFC, GPS, or biometric
  capability.
- User-created VM profiles or exposed VM tuning in the primary product.
- Shipping proprietary Google binaries in the public repository.

## Product invariants

1. One managed environment is the source of Android app and account state.
2. App launches produce or focus app-specific Mac windows.
3. Host file access is denied unless the user makes an explicit selection.
4. Runtime artifacts are signed, verified before use, and installed atomically.
5. Compatibility claims are backed by recorded app-level results.
6. Technical diagnostics remain available without becoming the normal workflow.
7. Failure messages describe user actions, not raw backend errors.

## Release gates

v1 cannot ship until all of these are true:

- A backend meets the objective criteria in
  [backend-decision.md](backend-decision.md).
- Google confirms an authorized GMS/Play route in writing, or the product
  contract is deliberately revised and communicated.
- Runtime licenses and notices are complete.
- The app and runtime distribution pass signing, notarization, integrity,
  update, rollback, and clean-machine tests.
- The published compatibility set meets its declared target.
