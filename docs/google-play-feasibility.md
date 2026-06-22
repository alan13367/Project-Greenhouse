# Google Play and GMS Feasibility

Assessment date: June 23, 2026.

Status: **unresolved release blocker**. There is a public route to begin the
conversation, but no authorization or certification outcome exists for
Greenhouse yet.

## Facts established from first-party documentation

- Google states that GMS is not part of AOSP and is available only through a
  license with Google: <https://www.android.com/gms/>.
- Android compatibility requires implementing Android, satisfying the matching
  Compatibility Definition Document (CDD), and passing the matching
  Compatibility Test Suite (CTS). Compatibility makes a device eligible to
  *consider* GMS licensing; it does not grant a license:
  <https://source.android.com/docs/compatibility/overview>.
- CTS includes automated tests and CTS Verifier manual tests:
  <https://source.android.com/docs/compatibility/cts>.
- Google publishes a GMS partner contact form. Greenhouse must use it to obtain
  a written determination for this Mac-hosted form factor:
  <https://www.android.com/gms/contact/>.
- Play Integrity can distinguish genuine certified devices and emulated
  environments. App developers may reject Greenhouse regardless of general app
  compatibility:
  <https://developer.android.com/google/play/integrity/overview>.

## Required path

1. Form a legal entity and provide the product, volume, countries, distribution
   channels, Android version, and “Other” form-factor details requested by the
   GMS partner form.
2. Ask Google in writing whether a persistent Android environment hosted on
   Apple Silicon Macs is eligible for GMS/Play licensing and which device
   category and requirements apply.
3. Select a pinned Android release only after backend feasibility. Use that
   release’s exact CDD, ARM CTS, CTS Verifier, and Google-provided private
   requirements.
4. Design the guest hardware profile and Greenhouse modifications to the CDD,
   not merely to successful boot.
5. Run CTS continuously and retain reports. Run all applicable CTS Verifier
   tests, documenting genuinely absent hardware features.
6. Complete Google’s licensing, certification, branding, security-update, and
   approval process before adding GMS to any public runtime.
7. Validate account creation/sign-in, purchase/license checks, install/update,
   Play Protect behavior, and recovery on production-signed builds.

## Requirements inventory

| Area | Greenhouse obligation | Current state |
| --- | --- | --- |
| CDD | Meet the exact CDD for the selected Android version and declared form factor/features | Version and form factor not yet selected |
| CTS | Pass the matching ARM suite; track retries and stable failures | Harness not integrated |
| CTS Verifier | Complete applicable manual/semi-automated tests, including display, audio, input, and connectivity | Test plan not yet mapped |
| GMS | Obtain license and private partner requirements; respect geography and required app set | Contact path identified; no agreement |
| Security updates | Define patch cadence, signed update channel, rollback, and vulnerability response | Policy drafted, implementation pending |
| Device identity | Use stable, authorized product identity and signing; never spoof another certified product | Design pending |
| Play Integrity | Measure verdicts honestly; never promise or bypass app-specific enforcement | Compatibility category defined |
| Google account and Play commerce | Validate sign-in, install, updates, entitlement, purchase, and restore | Fake flow only |

## Stop conditions

- Do not download unofficial “GApps” bundles into production.
- Do not copy keys, fingerprints, identifiers, or binaries from another
  certified device.
- Do not claim Google Play support until written authorization and candidate
  certification evidence exist.
- If Google declares the form factor ineligible, open a product-contract ADR.
  Do not silently replace the release requirement with an unofficial bundle.
