#!/usr/bin/env bash
# Compile the Android guest agent against the pinned platform API surface.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_DIR="$ROOT_DIR/artifacts/aosp-sdk-36"
STUB_JAR="$CACHE_DIR/android-test.jar"
STUB_SHA256="928defda1feb591189e947e52443bdf93d321b77e50863077368c92e1e33a267"
STUB_URL="https://android.googlesource.com/platform/prebuilts/sdk/+/refs/heads/android16-qpr2-release/36/test/android.jar?format=TEXT"
WORK_DIR="$CACHE_DIR/guest-agent-compile"

for tool in python3 javac jar; do
  command -v "$tool" >/dev/null || {
    echo "$tool is required for the guest-agent compile check." >&2
    exit 69
  }
done

mkdir -p "$CACHE_DIR"
if [[ ! -f "$STUB_JAR" ]] || \
   [[ "$(shasum -a 256 "$STUB_JAR" | awk '{print $1}')" != "$STUB_SHA256" ]]; then
  rm -f "$STUB_JAR"
  python3 - "$STUB_URL" "$STUB_JAR" "$STUB_SHA256" <<'PY'
import base64
import hashlib
import pathlib
import sys
import urllib.request

url, destination, expected = sys.argv[1:]
raw = urllib.request.urlopen(url, timeout=180).read()
data = base64.b64decode(raw)
actual = hashlib.sha256(data).hexdigest()
if actual != expected:
    raise SystemExit(f"AOSP SDK stub SHA-256 mismatch: {actual} != {expected}")
pathlib.Path(destination).write_bytes(data)
PY
fi

rm -rf "$WORK_DIR"
mkdir -p \
  "$WORK_DIR/hidden-src/android/hardware/input" \
  "$WORK_DIR/hidden-classes" \
  "$WORK_DIR/classes"

# The AOSP test stubs intentionally omit this @hide API even though
# platform_apis: true exposes it to the real Android build. Supply only the
# exact Android 16 QPR2 signature so javac can validate the rest of the agent.
cat >"$WORK_DIR/hidden-src/android/hardware/input/InputManager.java" <<'JAVA'
package android.hardware.input;

import android.view.InputEvent;

public class InputManager {
    public boolean injectInputEvent(InputEvent event, int mode) {
        throw new UnsupportedOperationException("compile-time stub");
    }
}
JAVA

javac \
  -source 17 \
  -target 17 \
  -cp "$STUB_JAR" \
  -d "$WORK_DIR/hidden-classes" \
  "$WORK_DIR/hidden-src/android/hardware/input/InputManager.java"
jar --create \
  --file "$WORK_DIR/hidden-input-api.jar" \
  -C "$WORK_DIR/hidden-classes" .

find "$ROOT_DIR/guest/app-window-agent/src" -name '*.java' -print0 \
  | xargs -0 javac \
      -Xlint:all \
      -Werror \
      -source 17 \
      -target 17 \
      -cp "$WORK_DIR/hidden-input-api.jar:$STUB_JAR" \
      -d "$WORK_DIR/classes"

echo "guest app-window agent compiles against Android 16 QPR2 test/platform APIs"
