# Runtime Licensing and Redistribution Inventory

Status: initial inventory. Every selected runtime component must gain an exact
version, source URL, license text, notice, source-offer obligation, and artifact
owner before a distributable runtime is assembled.

| Component | Expected license/status | Redistribution decision |
| --- | --- | --- |
| Greenhouse host code | Apache License 2.0 | Source and binaries may ship with license and notices |
| AOSP platform code | Predominantly Apache 2.0, component-specific exceptions | Pin exact manifests and generate a component bill of materials |
| Android Linux kernel | GPL-2.0-only plus component-specific terms | Publish corresponding source and build configuration for shipped binaries |
| QEMU, if selected | GPL-2.0 and component-specific compatible licenses | Legal review and corresponding source obligations required |
| Swift and Apple system frameworks | Apple toolchain/platform terms | Do not redistribute Apple frameworks separately |
| Google Play, GMS, Google apps | Proprietary; not part of AOSP | Never commit or redistribute without a written Google license |
| App/game fixtures | Third-party copyright | Use only purpose-built or properly licensed fixtures |
| User-provided APKs | User-controlled | Never redistribute; install only at the user’s request |

## Supply-chain rules

- No production signing keys, Google binaries, large runtime images, or
  copyrighted commercial app assets in Git.
- Runtime manifests enumerate every file, digest, size, origin, license, and
  required notice.
- Builds retain source revisions and scripts sufficient to reproduce
  open-source runtime components.
- Copyleft source and written offers are published with the corresponding
  runtime release where required.
- License scanning is a release check, not a substitute for human review.

`THIRD_PARTY_NOTICES.md` is intentionally small in Phase 1 because the fake
backend has no bundled third-party runtime.
