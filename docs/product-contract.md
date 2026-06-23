# Product Contract

Status: revised for the Community Runtime on June 23, 2026.

## Promise

Project Greenhouse lets everyday Mac users install and run compatible Android
apps through native-feeling Mac windows.

The normal flow is:

```text
Open Greenhouse → Install from F-Droid or a package → Open the app
```

Users manage apps, not virtual machines. Backend names, ADB, Android images,
ABIs, and resource tuning stay in Advanced Diagnostics.

## Supported v1 envelope

- Apple Silicon Macs running macOS 15.0 or later.
- One persistent, Greenhouse-managed Android system.
- A separate Mac window for each supported foreground Android app.
- ARM64 Android applications and pure Java/Kotlin applications.
- F-Droid and user-provided universal APKs or supported split APK sets.
- Optional microG-compatible Google API support.
- Keyboard, mouse, trackpad, audio, networking, and game controllers.
- Accelerated graphics for a measured compatibility set, when the graphics
  feasibility blocker is resolved.
- Direct-download distribution using Developer ID signing and notarization.

## Explicit non-goals

- Official Google Play Store or proprietary GMS in the Community Runtime.
- Claiming that microG is Google software, Google-certified, or universally
  compatible with Google APIs.
- Guaranteed Play Integrity, DRM, anti-cheat, billing, or licensing outcomes.
- Intel Mac support or x86/x86_64 Android application translation.
- Compatibility with every app, game, or phone-hardware feature.
- User-created VM profiles or exposed VM tuning in the primary product.

## Product invariants

1. One managed environment is the source of Android app and account state.
2. App launches produce or focus app-specific Mac windows.
3. Host file access is denied unless the user makes an explicit selection.
4. Runtime artifacts are signed, verified before use, and installed atomically.
5. Compatibility claims are backed by recorded app-level results.
6. Google compatibility is always labeled by provider: none, microG, or
   separately licensed GMS.
7. Technical diagnostics remain available without becoming the normal workflow.
8. Failure messages describe user actions, not raw backend errors.

## Release gates

v1 cannot ship until all of these are true:

- A backend meets the objective criteria in
  [backend-decision.md](backend-decision.md).
- The accelerated graphics and independent app-surface blockers are resolved.
- The Community Runtime builds reproducibly, boots, and passes its declared
  compatibility tests.
- Runtime licenses, source obligations, and notices are complete.
- The app and runtime distribution pass signing, notarization, integrity,
  update, rollback, and clean-machine tests.
- The published compatibility set meets its declared target.

Official Google Play remains a possible future, separately licensed product
track. It is not a v1 Community Runtime release gate.
