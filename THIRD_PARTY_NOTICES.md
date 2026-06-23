# Third-Party Notices

The source-built Greenhouse application links to Apple platform frameworks and
contains no committed Android runtime, proprietary Google software, emulator
binary, or third-party app/game asset.

Phase 2 scripts download pinned Alpine Linux test artifacts into an ignored
local artifacts directory. Those files and the locally installed QEMU binary
are development inputs and are not redistributed by this repository.

Phase 3 scripts can download these pinned Community Runtime inputs into the
same ignored artifacts area:

- microG Services Core, Companion/FakeStore, and GsfProxy — Apache License 2.0.
- F-Droid client — GNU General Public License v3.0 or later.
- F-Droid Privileged Extension — Apache License 2.0.
- LineageOS and Android platform sources — component-specific open-source
  licenses.
- Android Emulator engine and Ranchu/gfxstream sources or SDK packages —
  component-specific open-source licenses plus Android SDK terms for Google's
  packaged tools.
- scrcpy — Apache License 2.0; required only by the stock-AVD development proof
  and not linked into Greenhouse.

The lockfile records exact versions, sources, and SHA-256 values. These
development downloads are not redistributed by this repository. A runtime
release must include a generated version-specific notice, license set, and
corresponding-source obligation inventory. See `docs/runtime-licensing.md`.
