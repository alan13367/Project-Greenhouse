# Security Policy

The product app now contains a non-production Ranchu backend in addition to the
deterministic fake backend. Phase 3 adds a hash-pinned microG/F-Droid package
supply, an isolated localhost ADB server, and a display-stream protocol. No
downloaded APK, built Android image, emulator binary, proprietary Google
software, public network listener, or update service is committed to the
repository.

Please report vulnerabilities privately through GitHub’s **Report a
vulnerability** flow when available. If private reporting is unavailable, open
a minimal issue asking a maintainer for a private contact route; do not include
exploit details, credentials, personal data, or unreleased partner information.

Include the affected revision, macOS and hardware version, impact, reproduction
conditions, and any proposed mitigation. Maintainers will acknowledge a
complete report, triage severity, coordinate a fix and disclosure window, and
credit reporters who want attribution.

The initial threat model is in `docs/security.md`.
