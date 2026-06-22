#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Project Greenhouse development requires macOS." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Project Greenhouse targets Apple Silicon Macs." >&2
  exit 1
fi

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

echo "Using developer tools: $(xcrun --find swift)"
xcrun swift --version
echo "Running foundation tests…"
"$ROOT_DIR/scripts/build-and-test.sh"
echo "Bootstrap complete. Run ./script/build_and_run.sh to open Greenhouse."
