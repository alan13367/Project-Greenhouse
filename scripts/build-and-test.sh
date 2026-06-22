#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/GreenhouseMac"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$ACTIVE_DEVELOPER_DIR" == *"/CommandLineTools" ]]; then
    for XCODE_APP in /Applications/Xcode.app /Applications/Xcode-beta.app; do
      if [[ -d "$XCODE_APP/Contents/Developer" ]]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        break
      fi
    done
  fi
fi

xcrun swift build --package-path "$PACKAGE_DIR"
xcrun swift test --package-path "$PACKAGE_DIR"

while IFS= read -r -d '' json_file; do
  python3 -m json.tool "$json_file" >/dev/null
done < <(find "$ROOT_DIR/runtime" -name '*.json' -print0)
