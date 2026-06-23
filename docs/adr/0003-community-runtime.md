# ADR 0003: Adopt an Open Community Runtime for Phase 3

- Status: accepted
- Date: June 23, 2026

## Context

Google Mobile Services and the Google Play Store are proprietary and require a
license. Greenhouse does not currently have a legal entity, written Google
authorization, or a certified device program. Waiting for that path would
prevent useful open-source guest work, while copying a GApps bundle would be a
licensing and trust failure.

Phase 2 also found unresolved accelerated-graphics and independent app-surface
blockers. Those blockers remain; this decision only unblocks the guest-build
and service-compatibility track of Phase 3.

## Decision

Greenhouse v1 will target a Community Runtime based on pinned LineageOS 23.2,
microG, F-Droid, and local package installation.

- Use LineageOS restricted, system-only signature spoofing.
- Pin source revisions and downloaded APK SHA-256 values.
- Keep downloaded APKs and built Android images out of Git.
- Label the provider as microG in product state and UI.
- State explicitly that official Google Play is not included.
- Treat licensed GMS as a separate future distribution channel.

## Consequences

Phase 3 guest integration can proceed without claiming Google certification.
Many applications using Google APIs may work, but compatibility must be tested
per app. Apps depending on Play Integrity, Play billing/licensing, DRM,
anti-cheat, or proprietary Play Store behavior may remain unsupported.

The Phase 2 graphics and app-surface no-go remains a release blocker.
