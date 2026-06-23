#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/GreenhouseMac"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "Greenhouse's Mac host must be tested on macOS." >&2
  exit 1
}

[[ "$(uname -m)" == "arm64" ]] || {
  echo "Greenhouse requires an Apple Silicon Mac." >&2
  exit 1
}

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

"$ROOT_DIR/script/verify_community_runtime.sh"
"$ROOT_DIR/script/internal/compile_guest_agent.sh"

while IFS= read -r -d '' json_file; do
  python3 -m json.tool "$json_file" >/dev/null
done < <(find "$ROOT_DIR/runtime" -name '*.json' -print0)

for script_path in \
  "$ROOT_DIR/script/build_and_run.sh" \
  "$ROOT_DIR/script/prove_stock_runtime.sh" \
  "$ROOT_DIR/script/prove_community_runtime.sh" \
  "$ROOT_DIR/script/soak_runtime.sh" \
  "$ROOT_DIR/script/internal/compile_guest_agent.sh" \
  "$ROOT_DIR/script/build_community_runtime.sh" \
  "$ROOT_DIR/script/fetch_community_runtime.sh" \
  "$ROOT_DIR/script/verify_community_runtime.sh" \
  "$ROOT_DIR/script/generate_app_icon.sh"; do
  bash -n "$script_path"
done

test ! -e \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_cf_phone_arm64.mk"
grep -Fq 'greenhouse_sdk_phone_arm64-userdebug' \
  "$ROOT_DIR/guest/community-runtime/product/AndroidProducts.mk"
grep -Fq 'lineage_sdk_phone_arm64.mk' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'ro.greenhouse.virtual_hardware=ranchu' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'ro.greenhouse.graphics.transport=gfxstream' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'GreenhouseAppWindowAgent' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'VIRTUAL_DISPLAY_FLAG_TRUSTED' \
  "$ROOT_DIR/guest/app-window-agent/src/dev/greenhouse/agent/AppDisplaySession.java"
grep -Fq 'MediaCodec.createEncoderByType' \
  "$ROOT_DIR/guest/app-window-agent/src/dev/greenhouse/agent/AppDisplaySession.java"
grep -Fq 'setLaunchDisplayId' \
  "$ROOT_DIR/guest/app-window-agent/src/dev/greenhouse/agent/AppDisplaySession.java"
grep -Fq 'setDisplayId(displayId)' \
  "$ROOT_DIR/guest/app-window-agent/src/dev/greenhouse/agent/InputRouter.java"
grep -Fq 'RULE_MATCH_UID' \
  "$ROOT_DIR/guest/app-window-agent/src/dev/greenhouse/agent/AudioCapture.java"
grep -Fq 'cmd", "gpu", "vkjson' \
  "$ROOT_DIR/apps/GreenhouseMac/Sources/GreenhouseRuntime/Ranchu/RanchuRuntimeController.swift"
grep -Fq '"vulkanDevice"' \
  "$ROOT_DIR/runtime/schemas/phase3-proof.schema.json"
grep -Fq '"vulkanDevice"' \
  "$ROOT_DIR/runtime/schemas/phase3-community-proof.schema.json"

echo "Greenhouse build, tests, guest-agent compile, and source checks passed."
