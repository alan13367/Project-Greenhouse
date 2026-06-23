# Development Event Format

Greenhouse emits one versioned JSON object per line (NDJSON). The authoritative
schema is `runtime/schemas/development-event.schema.json`.

Required envelope fields:

- `schemaVersion`, currently `2`.
- UUID `id` and backend-local monotonic `sequence`.
- ISO-8601 `timestamp`.
- Stable `source`, `level`, machine-readable `name`, and human `message`.
- String-to-string `attributes`.
- Optional `statePatch` and typed `issue`.

Operation values use an explicit `kind` and optional `progress`; they do not
depend on Swift enum’s synthesized JSON representation.

Events are redacted before entering unified logging or the in-memory diagnostic
journal. Keys containing authorization, cookie, credential, password, secret,
token, or account are replaced. Email addresses are masked and the current
home-directory prefix becomes `~`.

Schema changes that remove or reinterpret a field require a new
`schemaVersion`. Additive optional fields may remain within a version when old
consumers safely ignore them.

Version 2 adds the explicit Google-service provider field and replaces the
Google Play installation operation with the Community Runtime store operation.
