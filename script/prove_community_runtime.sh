#!/usr/bin/env bash
# Exercise the built Community Runtime through the production Ranchu backend.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_DIR="${GREENHOUSE_SYSTEM_IMAGE_DIR:-$ROOT_DIR/artifacts/community-runtime/images}"
REPORT_DIR="$ROOT_DIR/artifacts/phase3/community-runtime"
REPORT_FILE="$REPORT_DIR/report.json"

if [[ ! -f "$IMAGE_DIR/system.img" \
    || ! -f "$IMAGE_DIR/userdata.img" \
    || ! -f "$IMAGE_DIR/kernel-ranchu" \
    || ! -f "$IMAGE_DIR/ramdisk.img" \
    || ! -f "$IMAGE_DIR/vendor.img" ]]; then
  echo "Community Runtime emulator images are missing under $IMAGE_DIR." >&2
  echo "Build them first with script/build_community_runtime.sh on Linux." >&2
  exit 69
fi

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for xcode in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    if [[ -d "$xcode/Contents/Developer" ]]; then
      export DEVELOPER_DIR="$xcode/Contents/Developer"
      break
    fi
  done
fi

mkdir -p "$REPORT_DIR"
export GREENHOUSE_SYSTEM_IMAGE_DIR="$IMAGE_DIR"
xcrun swift run \
  --package-path "$ROOT_DIR/apps/GreenhouseMac" \
  GreenhouseRuntimeProbe \
  >"$REPORT_FILE"

python3 -m json.tool "$REPORT_FILE" >/dev/null
python3 - "$REPORT_FILE" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
failures = []
if report["engine"] != "Android Emulator":
    failures.append("wrong engine")
if report["virtualHardware"] != "goldfish-ranchu":
    failures.append("wrong virtual hardware")
if not report["appWindowAgentResponsive"]:
    failures.append("app-window agent unavailable")
if not report["requiredPackagesPresent"]:
    failures.append("microG/F-Droid package set incomplete")
graphics = " ".join([
    report["renderer"],
    report["vulkanDevice"],
    report["restartRenderer"],
    report["restartVulkanDevice"],
]).lower()
if not report["vulkanDevice"] or not report["restartVulkanDevice"]:
    failures.append("active Vulkan device was not reported")
if any(name in graphics for name in ("swiftshader", "lavapipe", "software")):
    failures.append("graphics fell back to a software renderer")
if len({stream["displayID"] for stream in report["streams"]}) != 2:
    failures.append("two independent display IDs were not observed")
if any(stream["framesDecoded"] < 30 for stream in report["streams"]):
    failures.append("an app stream decoded fewer than 30 frames")
if not report["persistenceVerified"]:
    failures.append("userdata marker did not survive restart")
if failures:
    raise SystemExit("Community Runtime proof failed: " + "; ".join(failures))
PY

cat "$REPORT_FILE"
