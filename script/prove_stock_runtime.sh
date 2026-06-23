#!/usr/bin/env bash
# Reproduce the stock ARM64 AVD dual-window acceptance proof.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${GREENHOUSE_ANDROID_SDK_ROOT:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}}"
RUNTIME_DATA="${GREENHOUSE_RUNTIME_DATA:-$HOME/Library/Application Support/Greenhouse/Runtime}"
AVD_HOME="${GREENHOUSE_AVD_HOME:-${ANDROID_AVD_HOME:-$HOME/.android/avd}}"
AVD_NAME="${GREENHOUSE_AVD_NAME:-greenhouse_stock}"
EMULATOR_PORT="${GREENHOUSE_EMULATOR_PORT:-5554}"
ADB_SERVER_PORT="${GREENHOUSE_ADB_SERVER_PORT:-5038}"
SERIAL="emulator-$EMULATOR_PORT"
APP_ONE="${GREENHOUSE_PROOF_APP_ONE:-com.android.settings}"
APP_TWO="${GREENHOUSE_PROOF_APP_TWO:-com.android.documentsui}"
DURATION_SECONDS="${GREENHOUSE_PROOF_DURATION_SECONDS:-20}"
ARTIFACT_DIR="$ROOT_DIR/artifacts/phase3/stock-avd"
EMULATOR="$SDK_ROOT/emulator/emulator"
ADB="$SDK_ROOT/platform-tools/adb"
SCRCPY="${GREENHOUSE_SCRCPY:-$(command -v scrcpy || true)}"
FFPROBE="${GREENHOUSE_FFPROBE:-$(command -v ffprobe || true)}"

for executable in "$EMULATOR" "$ADB" "$SCRCPY" "$FFPROBE"; do
  if [[ -z "$executable" || ! -x "$executable" ]]; then
    echo "required runtime proof tool is missing: ${executable:-scrcpy}" >&2
    exit 69
  fi
done

SCRCPY_MAJOR="$("$SCRCPY" --version | awk 'NR == 1 {split($2, v, "."); print v[1]}')"
if [[ -z "$SCRCPY_MAJOR" || "$SCRCPY_MAJOR" -lt 4 ]]; then
  echo "scrcpy 4.0 or newer is required for flex virtual displays." >&2
  exit 69
fi

mkdir -p \
  "$ARTIFACT_DIR" \
  "$RUNTIME_DATA/android-home" \
  "$AVD_HOME" \
  "$RUNTIME_DATA/adb-home" \
  "$RUNTIME_DATA/logs"
find "$ARTIFACT_DIR" -mindepth 1 -maxdepth 1 -type f -delete

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_USER_HOME="$RUNTIME_DATA/android-home"
export ANDROID_AVD_HOME="$AVD_HOME"
export HOME="$RUNTIME_DATA/adb-home"
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ADB_SERVER_SOCKET="tcp:127.0.0.1:$ADB_SERVER_PORT"
export ADB="$ADB"

adb_private() {
  "$ADB" -P "$ADB_SERVER_PORT" -s "$SERIAL" "$@"
}

now_ns() {
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC \
    -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1e9'
}

stop_emulator() {
  adb_private emu kill >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    if [[ "$(adb_private get-state 2>/dev/null || true)" != "device" ]]; then
      break
    fi
    sleep 1
  done
  if [[ -n "${EMULATOR_PID:-}" ]]; then
    for _ in $(seq 1 30); do
      if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    if kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
      kill "$EMULATOR_PID" >/dev/null 2>&1 || true
    fi
    wait "$EMULATOR_PID" >/dev/null 2>&1 || true
  fi
}

wait_for_emulator_boot() {
  local attempt
  for attempt in $(seq 1 180); do
    if ! kill -0 "$EMULATOR_PID" >/dev/null 2>&1; then
      return 2
    fi
    if [[ "$(adb_private get-state 2>/dev/null || true)" != "device" ]]; then
      if (( attempt % 5 == 0 )); then
        "$ADB" -P "$ADB_SERVER_PORT" kill-server >/dev/null 2>&1 || true
        "$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null
      fi
      sleep 1
      continue
    fi
    if [[ "$(adb_private shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

select_launchable_app() {
  local requested="$1"
  shift
  local package
  for package in "$requested" "$@"; do
    if adb_private shell cmd package resolve-activity \
        --brief \
        -a android.intent.action.MAIN \
        -c android.intent.category.LAUNCHER \
        -p "$package" 2>/dev/null \
        | grep -q '/'; then
      printf '%s\n' "$package"
      return
    fi
  done
  return 1
}

cleanup() {
  if [[ -n "${PACING_INPUT_PID:-}" ]]; then
    kill "$PACING_INPUT_PID" >/dev/null 2>&1 || true
    wait "$PACING_INPUT_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${SCRCPY_ONE_PID:-}" ]]; then kill "$SCRCPY_ONE_PID" >/dev/null 2>&1 || true; fi
  if [[ -n "${SCRCPY_TWO_PID:-}" ]]; then kill "$SCRCPY_TWO_PID" >/dev/null 2>&1 || true; fi
  if [[ -n "${SCRCPY_ONE_PID:-}" ]]; then wait "$SCRCPY_ONE_PID" >/dev/null 2>&1 || true; fi
  if [[ -n "${SCRCPY_TWO_PID:-}" ]]; then wait "$SCRCPY_TWO_PID" >/dev/null 2>&1 || true; fi
  if [[ "${GREENHOUSE_KEEP_EMULATOR:-0}" != "1" ]]; then
    stop_emulator
  fi
}
trap cleanup EXIT

"$ADB" -P "$ADB_SERVER_PORT" kill-server >/dev/null 2>&1 || true
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null
if [[ "$(adb_private get-state 2>/dev/null || true)" == "device" ]]; then
  stop_emulator
  EMULATOR_PID=""
fi
"$ADB" -P "$ADB_SERVER_PORT" kill-server >/dev/null 2>&1 || true
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

BOOT_STARTED_NS="$(now_ns)"
"$EMULATOR" \
  -avd "$AVD_NAME" \
  -port "$EMULATOR_PORT" \
  -accel on \
  -gpu host \
  -no-window \
  -no-boot-anim \
  -no-snapshot \
  -netdelay none \
  -netspeed full \
  >"$ARTIFACT_DIR/emulator.log" 2>&1 &
EMULATOR_PID=$!

if wait_for_emulator_boot; then
  :
else
  status=$?
  if [[ "$status" == "2" ]]; then
    echo "Android Emulator exited before boot completed." >&2
    exit 70
  fi
  echo "Android boot timed out." >&2
  exit 70
fi
BOOT_COMPLETED_NS="$(now_ns)"

APP_ONE="$(select_launchable_app \
  "$APP_ONE" \
  com.android.settings)" || {
  echo "No launchable first stock app was found." >&2
  exit 70
}
APP_TWO="$(select_launchable_app \
  "$APP_TWO" \
  com.google.android.documentsui \
  com.google.android.deskclock \
  com.android.camera2 \
  com.android.chrome \
  com.android.deskclock \
  com.android.calculator2 \
  com.google.android.contacts \
  com.android.contacts \
  com.android.gallery3d)" || {
  echo "No launchable second stock app was found." >&2
  exit 70
}
if [[ "$APP_ONE" == "$APP_TWO" ]]; then
  echo "The stock proof requires two distinct launchable packages." >&2
  exit 70
fi

"$EMULATOR" -accel-check >"$ARTIFACT_DIR/acceleration.txt" 2>&1 || true
adb_private shell dumpsys SurfaceFlinger >"$ARTIFACT_DIR/surfaceflinger.txt"
adb_private shell getprop >"$ARTIFACT_DIR/getprop.txt"
adb_private shell cmd gpu vkjson >"$ARTIFACT_DIR/vulkan.json" 2>"$ARTIFACT_DIR/vulkan-error.txt" || true
adb_private shell dumpsys display >"$ARTIFACT_DIR/displays-before.txt"
adb_private shell dumpsys media.codec \
  >"$ARTIFACT_DIR/media-codecs.txt" \
  2>"$ARTIFACT_DIR/media-codecs-error.txt" || true
adb_private shell pm list features >"$ARTIFACT_DIR/features.txt"

adb_private shell sh -c \
  "'printf greenhouse-phase3 > /data/local/tmp/greenhouse-persistence-marker'"
adb_private forward --remove tcp:28183 >/dev/null 2>&1 || true
adb_private forward --remove tcp:28184 >/dev/null 2>&1 || true

APP_ONE_STARTED_NS="$(now_ns)"
: >"$ARTIFACT_DIR/app-one.log"
rm -f "$ARTIFACT_DIR/app-one.mkv"
"$SCRCPY" \
  --serial "$SERIAL" \
  --new-display=1024x768/240 \
  --start-app="$APP_ONE" \
  --flex-display \
  --display-ime-policy=local \
  --window-title="Greenhouse Proof — App One" \
  --force-adb-forward \
  --port=28183 \
  --print-fps \
  --video-codec=h264 \
  --video-bit-rate=12M \
  --max-fps=60 \
  --gamepad=uhid \
  --record="$ARTIFACT_DIR/app-one.mkv" \
  >>"$ARTIFACT_DIR/app-one.log" 2>&1 &
SCRCPY_ONE_PID=$!

APP_ONE_READY_NS=""
for _ in $(seq 1 300); do
  if grep -q 'New display: .*id=' "$ARTIFACT_DIR/app-one.log"; then
    APP_ONE_READY_NS="$(now_ns)"
    break
  fi
  if ! kill -0 "$SCRCPY_ONE_PID" >/dev/null 2>&1; then
    echo "The first scrcpy virtual-display session exited during startup." >&2
    exit 70
  fi
  sleep 0.1
done
if [[ -z "$APP_ONE_READY_NS" ]]; then
  echo "The first scrcpy session did not create a display before the deadline." >&2
  exit 70
fi
sleep 1

APP_TWO_STARTED_NS="$(now_ns)"
: >"$ARTIFACT_DIR/app-two.log"
rm -f "$ARTIFACT_DIR/app-two.mkv"
"$SCRCPY" \
  --serial "$SERIAL" \
  --new-display=900x700/240 \
  --start-app="$APP_TWO" \
  --flex-display \
  --display-ime-policy=local \
  --window-title="Greenhouse Proof — App Two" \
  --force-adb-forward \
  --port=28184 \
  --print-fps \
  --video-codec=h264 \
  --video-bit-rate=12M \
  --max-fps=60 \
  --no-audio \
  --record="$ARTIFACT_DIR/app-two.mkv" \
  >>"$ARTIFACT_DIR/app-two.log" 2>&1 &
SCRCPY_TWO_PID=$!

APP_TWO_READY_NS=""
for _ in $(seq 1 300); do
  if grep -q 'New display: .*id=' "$ARTIFACT_DIR/app-two.log"; then
    APP_TWO_READY_NS="$(now_ns)"
    break
  fi
  if ! kill -0 "$SCRCPY_TWO_PID" >/dev/null 2>&1; then
    echo "The second scrcpy virtual-display session exited during startup." >&2
    exit 70
  fi
  sleep 0.1
done

if [[ -z "$APP_TWO_READY_NS" ]]; then
  echo "The second scrcpy session did not create a display before the deadline." >&2
  exit 70
fi
if ! kill -0 "$SCRCPY_ONE_PID" >/dev/null 2>&1; then
  echo "The first scrcpy session exited while the second was starting." >&2
  exit 70
fi
DISPLAY_ONE="$(
  sed -nE 's/.*New display: .*\(id=([0-9]+)\).*/\1/p' \
    "$ARTIFACT_DIR/app-one.log" | tail -1
)"
DISPLAY_TWO="$(
  sed -nE 's/.*New display: .*\(id=([0-9]+)\).*/\1/p' \
    "$ARTIFACT_DIR/app-two.log" | tail -1
)"
if [[ -z "$DISPLAY_ONE" || -z "$DISPLAY_TWO" || "$DISPLAY_ONE" == "$DISPLAY_TWO" ]]; then
  echo "Could not prove two distinct scrcpy virtual display IDs." >&2
  exit 70
fi

adb_private shell dumpsys display >"$ARTIFACT_DIR/displays-two-apps.txt"
TASK_ROUTING_VERIFIED=false
for _ in $(seq 1 100); do
  adb_private shell dumpsys activity activities \
    >"$ARTIFACT_DIR/activities-two-apps.txt"
  if python3 - \
      "$ARTIFACT_DIR/activities-two-apps.txt" \
      "$APP_ONE" \
      "$DISPLAY_ONE" \
      "$APP_TWO" \
      "$DISPLAY_TWO" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(errors="replace")

def task_on_display(package_name, display_id):
    match = re.search(
        rf"^Display #{display_id} \(activities from top to bottom\):\n"
        rf"(.*?)(?=^Display #\d+ \(activities from top to bottom\):|\Z)",
        text,
        re.M | re.S,
    )
    return bool(match and package_name in match.group(1))

raise SystemExit(
    0
    if task_on_display(sys.argv[2], int(sys.argv[3]))
    and task_on_display(sys.argv[4], int(sys.argv[5]))
    else 1
)
PY
  then
    TASK_ROUTING_VERIFIED=true
    break
  fi
  sleep 0.1
done
if [[ "$TASK_ROUTING_VERIFIED" != "true" ]]; then
  echo "Both app tasks were not routed to their assigned displays." >&2
  exit 70
fi
adb_private shell wm size -d "$DISPLAY_ONE" >"$ARTIFACT_DIR/display-one-size-before.txt"
adb_private shell wm size -d "$DISPLAY_TWO" >"$ARTIFACT_DIR/display-two-size-before.txt"

INPUT_RTT_FILE="$ARTIFACT_DIR/input-command-rtt-ms.txt"
: >"$INPUT_RTT_FILE"
for index in $(seq 1 20); do
  target_display="$DISPLAY_ONE"
  if (( index % 2 == 0 )); then
    target_display="$DISPLAY_TWO"
  fi
  input_started_ns="$(now_ns)"
  adb_private shell input --display "$target_display" swipe 500 600 500 300 180 \
    >/dev/null
  input_finished_ns="$(now_ns)"
  python3 - "$input_started_ns" "$input_finished_ns" >>"$INPUT_RTT_FILE" <<'PY'
import sys
print((int(sys.argv[2]) - int(sys.argv[1])) / 1_000_000)
PY
done

RESIZE_ATTEMPTED=false
RESIZE_SUCCEEDED=false
if command -v osascript >/dev/null; then
  RESIZE_ATTEMPTED=true
  if osascript <<'APPLESCRIPT' >/dev/null 2>&1
tell application "System Events"
  repeat with p in application processes whose name is "scrcpy"
    repeat with w in windows of p
      if name of w contains "Greenhouse Proof" then
        set size of w to {1180, 820}
      end if
    end repeat
  end repeat
end tell
APPLESCRIPT
  then
    RESIZE_SUCCEEDED=true
  fi
fi

(
  for index in $(seq 1 $((DURATION_SECONDS * 5))); do
    target_display="$DISPLAY_ONE"
    if (( index % 2 == 0 )); then
      target_display="$DISPLAY_TWO"
    fi
    if (( index % 4 < 2 )); then
      adb_private shell input --display "$target_display" \
        swipe 500 620 500 260 100 >/dev/null 2>&1 || true
    else
      adb_private shell input --display "$target_display" \
        swipe 500 260 500 620 100 >/dev/null 2>&1 || true
    fi
    sleep 0.1
  done
) &
PACING_INPUT_PID=$!
sleep "$DURATION_SECONDS"
wait "$PACING_INPUT_PID" >/dev/null 2>&1 || true
PACING_INPUT_PID=""
adb_private shell dumpsys display >"$ARTIFACT_DIR/displays-after-resize.txt"
adb_private shell wm size -d "$DISPLAY_ONE" >"$ARTIFACT_DIR/display-one-size-after.txt"
adb_private shell wm size -d "$DISPLAY_TWO" >"$ARTIFACT_DIR/display-two-size-after.txt"

if [[ "$RESIZE_SUCCEEDED" == "true" ]]; then
  if cmp -s \
      "$ARTIFACT_DIR/display-one-size-before.txt" \
      "$ARTIFACT_DIR/display-one-size-after.txt" \
      && cmp -s \
      "$ARTIFACT_DIR/display-two-size-before.txt" \
      "$ARTIFACT_DIR/display-two-size-after.txt"; then
    RESIZE_SUCCEEDED=false
  fi
fi

kill "$SCRCPY_ONE_PID" "$SCRCPY_TWO_PID" >/dev/null 2>&1 || true
wait "$SCRCPY_ONE_PID" >/dev/null 2>&1 || true
wait "$SCRCPY_TWO_PID" >/dev/null 2>&1 || true
SCRCPY_ONE_PID=""
SCRCPY_TWO_PID=""
adb_private shell dumpsys display >"$ARTIFACT_DIR/displays-after-close.txt"
DISPLAY_LIFECYCLE_VERIFIED=true
if grep -Eq "mDisplayId=($DISPLAY_ONE|$DISPLAY_TWO)([^0-9]|$)" \
    "$ARTIFACT_DIR/displays-after-close.txt"; then
  DISPLAY_LIFECYCLE_VERIFIED=false
fi

"$FFPROBE" -v error \
  -select_streams v:0 \
  -show_entries frame=best_effort_timestamp_time \
  -of csv=p=0 \
  "$ARTIFACT_DIR/app-one.mkv" >"$ARTIFACT_DIR/app-one-frame-times.txt"
"$FFPROBE" -v error \
  -select_streams v:0 \
  -show_entries frame=best_effort_timestamp_time \
  -of csv=p=0 \
  "$ARTIFACT_DIR/app-two.mkv" >"$ARTIFACT_DIR/app-two-frame-times.txt"

PERSISTENCE_VERIFIED=false
if [[ "${GREENHOUSE_SKIP_PERSISTENCE_RESTART:-0}" != "1" ]]; then
  stop_emulator
  EMULATOR_PID=""
  "$EMULATOR" \
    -avd "$AVD_NAME" \
    -port "$EMULATOR_PORT" \
    -accel on \
    -gpu host \
    -no-window \
    -no-boot-anim \
    -no-snapshot \
  >"$ARTIFACT_DIR/emulator-restart.log" 2>&1 &
  EMULATOR_PID=$!
  if wait_for_emulator_boot \
      && [[ "$(adb_private shell cat /data/local/tmp/greenhouse-persistence-marker 2>/dev/null | tr -d '\r')" == "greenhouse-phase3" ]]; then
    PERSISTENCE_VERIFIED=true
  fi
fi

export BOOT_STARTED_NS BOOT_COMPLETED_NS RESIZE_ATTEMPTED RESIZE_SUCCEEDED
export PERSISTENCE_VERIFIED APP_ONE APP_TWO AVD_NAME SERIAL ARTIFACT_DIR
export APP_ONE_STARTED_NS APP_ONE_READY_NS APP_TWO_STARTED_NS APP_TWO_READY_NS
export DISPLAY_ONE DISPLAY_TWO DISPLAY_LIFECYCLE_VERIFIED
python3 - <<'PY' >"$ARTIFACT_DIR/report.json"
import json
import math
import os
import pathlib
import re
import statistics

artifacts = pathlib.Path(os.environ["ARTIFACT_DIR"])
properties = (artifacts / "getprop.txt").read_text(errors="replace")
surface = (artifacts / "surfaceflinger.txt").read_text(errors="replace")
displays = (artifacts / "displays-two-apps.txt").read_text(errors="replace")
activities = (artifacts / "activities-two-apps.txt").read_text(errors="replace")
features = (artifacts / "features.txt").read_text(errors="replace")
vulkan_text = (artifacts / "vulkan.json").read_text(errors="replace")

def prop(name):
    match = re.search(rf"^\[{re.escape(name)}\]: \[(.*)\]$", properties, re.M)
    return match.group(1) if match else ""

def frame_pacing(path):
    timestamps = []
    for line in path.read_text(errors="replace").splitlines():
        try:
            timestamps.append(float(line.strip().split(",", 1)[0]))
        except ValueError:
            pass
    intervals = [new - old for old, new in zip(timestamps, timestamps[1:]) if new > old]
    if not intervals:
        return {
            "frames": len(timestamps),
            "meanFramesPerSecond": None,
            "intervalJitterMilliseconds": None,
            "p95IntervalMilliseconds": None,
            "longFrameRatio": None,
        }
    median = statistics.median(intervals)
    p95_index = min(int((len(intervals) - 1) * 0.95), len(intervals) - 1)
    return {
        "frames": len(timestamps),
        "meanFramesPerSecond": 1 / statistics.fmean(intervals),
        "intervalJitterMilliseconds": statistics.pstdev(intervals) * 1000,
        "p95IntervalMilliseconds": sorted(intervals)[p95_index] * 1000,
        "longFrameRatio": sum(value > median * 1.5 for value in intervals) / len(intervals),
    }

def float_samples(path):
    return [
        float(line)
        for line in path.read_text(errors="replace").splitlines()
        if line.strip()
    ]

app_one_pacing = frame_pacing(artifacts / "app-one-frame-times.txt")
app_two_pacing = frame_pacing(artifacts / "app-two-frame-times.txt")
rtt = float_samples(artifacts / "input-command-rtt-ms.txt")
virtual_display_devices = set(
    re.findall(
        r'DisplayDeviceInfo\{"scrcpy": uniqueId="([^"]+)".*?type VIRTUAL',
        displays,
    )
)
virtual_displays = len(virtual_display_devices)
renderer_match = re.search(r"GLES:\s*(.+)", surface)
renderer = renderer_match.group(1).strip() if renderer_match else prop("ro.hardware.egl")
vulkan_level = re.search(r"android\.hardware\.vulkan\.level(?:=|:)([^\r\n]+)", features)
vulkan_version = re.search(r"android\.hardware\.vulkan\.version(?:=|:)([^\r\n]+)", features)

def find_json_string(value, key):
    if isinstance(value, dict):
        candidate = value.get(key)
        if isinstance(candidate, str) and candidate:
            return candidate
        for nested in value.values():
            found = find_json_string(nested, key)
            if found:
                return found
    elif isinstance(value, list):
        for nested in value:
            found = find_json_string(nested, key)
            if found:
                return found
    return ""

try:
    vulkan_json = json.loads(vulkan_text)
except json.JSONDecodeError:
    vulkan_json = {}
vulkan_device = find_json_string(vulkan_json, "deviceName")
vulkan_driver = (
    find_json_string(vulkan_json, "driverName")
    or find_json_string(vulkan_json, "driverInfo")
)

def task_on_display(package_name, display_id):
    section = re.search(
        rf"^Display #{display_id} \(activities from top to bottom\):\n"
        rf"(.*?)(?=^Display #\d+ \(activities from top to bottom\):|\Z)",
        activities,
        re.M | re.S,
    )
    return bool(section and package_name in section.group(1))

tasks_routed = (
    task_on_display(os.environ["APP_ONE"], int(os.environ["DISPLAY_ONE"]))
    and task_on_display(os.environ["APP_TWO"], int(os.environ["DISPLAY_TWO"]))
)

report = {
    "schemaVersion": 1,
    "avd": os.environ["AVD_NAME"],
    "serial": os.environ["SERIAL"],
    "engine": "Android Emulator",
    "cpuAcceleration": "HVF",
    "graphicsMode": "host",
    "renderer": renderer,
    "glesVersion": prop("ro.opengles.version"),
    "vulkanLevel": vulkan_level.group(1).strip() if vulkan_level else "",
    "vulkanVersion": vulkan_version.group(1).strip() if vulkan_version else "",
    "vulkanDevice": vulkan_device,
    "vulkanDriver": vulkan_driver,
    "bootMilliseconds": (
        int(os.environ["BOOT_COMPLETED_NS"]) - int(os.environ["BOOT_STARTED_NS"])
    ) / 1_000_000,
    "apps": [os.environ["APP_ONE"], os.environ["APP_TWO"]],
    "displayIds": [int(os.environ["DISPLAY_ONE"]), int(os.environ["DISPLAY_TWO"])],
    "virtualDisplayCountObserved": virtual_displays,
    "twoAppDisplaysObserved": virtual_displays >= 2,
    "tasksRoutedToDisplays": tasks_routed,
    "videoStartupMilliseconds": {
        "appOne": (
            int(os.environ["APP_ONE_READY_NS"]) - int(os.environ["APP_ONE_STARTED_NS"])
        ) / 1_000_000,
        "appTwo": (
            int(os.environ["APP_TWO_READY_NS"]) - int(os.environ["APP_TWO_STARTED_NS"])
        ) / 1_000_000,
    },
    "videoStartupNote": (
        "Host launch to scrcpy virtual-display creation; final ffprobe frame "
        "counts verify that encoded video followed."
    ),
    "inputCommandRoundTripMilliseconds": {
        "mean": statistics.fmean(rtt) if rtt else None,
        "p95": sorted(rtt)[min(int((len(rtt) - 1) * 0.95), len(rtt) - 1)] if rtt else None,
        "samples": len(rtt),
    },
    "framePacing": {
        "appOne": app_one_pacing,
        "appTwo": app_two_pacing,
    },
    "framePacingWorkload": "alternating display-targeted swipe animations",
    "frameRateMean": statistics.fmean(
        value
        for value in [
            app_one_pacing["meanFramesPerSecond"],
            app_two_pacing["meanFramesPerSecond"],
        ]
        if value is not None
    ) if any(
        value is not None
        for value in [
            app_one_pacing["meanFramesPerSecond"],
            app_two_pacing["meanFramesPerSecond"],
        ]
    ) else None,
    "frameRateSampleJitter": statistics.fmean(
        value
        for value in [
            app_one_pacing["intervalJitterMilliseconds"],
            app_two_pacing["intervalJitterMilliseconds"],
        ]
        if value is not None
    ) if any(
        value is not None
        for value in [
            app_one_pacing["intervalJitterMilliseconds"],
            app_two_pacing["intervalJitterMilliseconds"],
        ]
    ) else None,
    "resizeAttempted": os.environ["RESIZE_ATTEMPTED"] == "true",
    "resizeAutomationSucceeded": os.environ["RESIZE_SUCCEEDED"] == "true",
    "displayLifecycleVerified": os.environ["DISPLAY_LIFECYCLE_VERIFIED"] == "true",
    "persistenceVerified": os.environ["PERSISTENCE_VERIFIED"] == "true",
    "inputLatencyMilliseconds": statistics.fmean(rtt) if rtt else None,
    "inputLatencyNote": (
        "ADB targeted-input command round trip; integrated Greenhouse streams "
        "also report clock-synchronized decode and Metal presentation latency."
    ),
}
print(json.dumps(report, indent=2, sort_keys=True))
PY

python3 -m json.tool "$ARTIFACT_DIR/report.json" >/dev/null
cat "$ARTIFACT_DIR/report.json"

if [[ "${GREENHOUSE_ALLOW_PARTIAL_PROOF:-0}" != "1" ]]; then
  python3 - "$ARTIFACT_DIR/report.json" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
failures = []
if not report["twoAppDisplaysObserved"]:
    failures.append("two virtual displays were not observed")
if report["bootMilliseconds"] < 1_000:
    failures.append("boot timing was contaminated by a stale emulator transport")
if any(value < 0 for value in report["videoStartupMilliseconds"].values()):
    failures.append("a video startup measurement was negative")
if not report["tasksRoutedToDisplays"]:
    failures.append("both app tasks were not observed on their assigned displays")
if not report["resizeAutomationSucceeded"]:
    failures.append("virtual-display resize was not verified")
if not report["displayLifecycleVerified"]:
    failures.append("virtual displays survived after both clients closed")
if not report["persistenceVerified"]:
    failures.append("userdata marker did not survive restart")
if "swiftshader" in report["renderer"].lower():
    failures.append("renderer fell back to SwiftShader")
if not report["vulkanLevel"] or not report["vulkanVersion"]:
    failures.append("Vulkan feature declarations were not observed")
if not report["vulkanDevice"]:
    failures.append("an active Vulkan device was not observed")
graphics = " ".join([
    report["renderer"],
    report["vulkanDevice"],
    report["vulkanDriver"],
]).lower()
if any(name in graphics for name in ("swiftshader", "lavapipe", "software")):
    failures.append("graphics fell back to a software renderer")
for name, pacing in report["framePacing"].items():
    if pacing["frames"] < 30:
        failures.append(f"{name} produced fewer than 30 measured video frames")
if failures:
    raise SystemExit("Phase 3 stock proof failed: " + "; ".join(failures))
PY
fi
