# Initial Threat Model

## Assets

- User Google credentials, app data, purchases, and tokens.
- Host files selected by the user.
- Android runtime integrity and persistent guest data.
- Runtime signing keys, update metadata, and release credentials.
- Private host/guest control channels and diagnostics.

## Trust boundaries

```text
Internet / update service
        ↓ signed artifacts
Greenhouse host process
        ↔ private control, display, input, and audio channels
Android guest and installed apps
        ↔ explicitly selected host files only
macOS user account and Keychain
```

Android apps and user-provided APKs are untrusted. The guest is a containment
boundary, not a source of trust. Network responses and diagnostics attachments
are untrusted input.

## Initial threats and controls

| Threat | Initial control |
| --- | --- |
| Malicious or replaced runtime | Signed manifest, digest verification, atomic install, rollback |
| Compromised update channel | TLS plus offline artifact signature verification and version policy |
| Guest escape or backend vulnerability | Minimal devices/channels, sandbox review, patch SLA, backend hardening |
| Arbitrary host file access | No shared home directory; user-selected files copied through a narrow broker |
| Public ADB or control socket | Local/private transport, authentication, no wildcard network listener |
| Credential leakage in logs | Structured allowlisted fields, sensitive-key redaction, email/home-path masking |
| Malicious APK | Clear provenance, package metadata, isolated guest install, no host execution |
| Persistent data corruption | Journaling, atomic updates, graceful shutdown, backups/migration tests |
| Controller/input injection to wrong app | Task-to-window focus ownership and explicit routing |
| Supply-chain compromise | Pinned sources, reproducible metadata, SBOM, code review, protected releases |
| Signing-key theft | Keys outside Git, least-privilege CI, rotation and revocation plan |
| Diagnostics privacy leak | Preview/export consent, redaction, bounded retention |

## Security invariants

- Never execute code from an unverified runtime package.
- Never expose the guest bridge beyond the local machine.
- Never mount the user’s home directory into Android.
- Never log credentials, cookies, authorization headers, account identifiers,
  or full user paths.
- Never bypass Play Integrity, DRM, anti-cheat, or certification controls.

Phase 1 implements structured logging redaction and keeps the fake backend free
of external listeners and runtime artifacts. Runtime verification, sandboxing,
entitlements, and update security are future implementation gates.
