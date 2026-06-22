# Distribution Decision

Decision: ship direct download first. Reconsider the Mac App Store only after
the final backend, sandbox, entitlement, runtime-download, and review-policy
requirements are proven.

## Direct-download release contract

Production releases will:

1. Build reproducibly from a tagged source revision.
2. Sign the host app and nested code with Developer ID.
3. Enable hardened runtime and only reviewed entitlements.
4. Submit the release artifact to Apple notarization with `notarytool`.
5. Staple and validate the notarization ticket.
6. Publish checksums and signed update metadata.
7. Verify installation and update on a clean supported Mac.

Apple documents Developer ID as the mechanism for software distributed outside
the Mac App Store and recommends notarization so Gatekeeper can validate it:
<https://developer.apple.com/developer-id/>.

Virtualization.framework requires the
`com.apple.security.virtualization` entitlement:
<https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.virtualization>.

## Why the Mac App Store is deferred

The App Store is not rejected permanently. It is deferred because the backend,
downloaded runtime, executable-code rules, sandbox file topology, entitlements,
and review treatment must be evaluated together. A later ADR may approve an
App Store build only after a signed candidate passes sandboxed runtime download,
launch, update, and App Review preflight without weakening the product.
