# Contributing

Project Greenhouse welcomes focused issues, experiments, documentation, tests,
and implementation changes that preserve the product contract.

## Before coding

- Read `docs/product-contract.md`.
- Open or reference an issue for changes that alter architecture, compatibility,
  runtime contents, security boundaries, licensing, or distribution.
- Use an ADR for durable decisions with multiple credible options.

## Development

```bash
./script/test.sh
./script/build_and_run.sh --verify
```

Pull requests should be small enough to review, explain user-visible behavior,
include tests for state/failure changes, and update relevant documentation.
Never commit Android images, downloaded QEMU binaries, proprietary Google
software, signing material, credentials, commercial app/game assets, or user
diagnostics.

Contributions are submitted under the repository’s Apache License 2.0 without a
separate contributor license agreement at this stage. Contributors must have
the right to submit their work and preserve third-party notices.
