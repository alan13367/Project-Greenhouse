#!/usr/bin/env bash
# Repeatedly cold-start the runtime to measure lifecycle reliability.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${GREENHOUSE_ANDROID_SDK_ROOT:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}}"
RUNTIME_DATA="${GREENHOUSE_RUNTIME_DATA:-$HOME/Library/Application Support/Greenhouse/Runtime}"
AVD_HOME="${GREENHOUSE_AVD_HOME:-${ANDROID_AVD_HOME:-$HOME/.android/avd}}"
AVD_NAME="${GREENHOUSE_AVD_NAME:-greenhouse_stock}"
EMULATOR_PORT="${GREENHOUSE_EMULATOR_PORT:-5554}"
ADB_SERVER_PORT="${GREENHOUSE_ADB_SERVER_PORT:-5038}"
SYSTEM_IMAGE_DIR="${GREENHOUSE_SYSTEM_IMAGE_DIR:-}"
CYCLES="${GREENHOUSE_SOAK_CYCLES:-50}"
SERIAL="emulator-$EMULATOR_PORT"
EMULATOR="$SDK_ROOT/emulator/emulator"
ADB="$SDK_ROOT/platform-tools/adb"
ARTIFACT_DIR="$ROOT_DIR/artifacts/phase3/lifecycle-soak"
RESULTS="$ARTIFACT_DIR/cycles.ndjson"

for executable in "$EMULATOR" "$ADB"; do
  if [[ ! -x "$executable" ]]; then
    echo "required runtime soak tool is missing: $executable" >&2
    exit 69
  fi
done

mkdir -p \
  "$ARTIFACT_DIR" \
  "$RUNTIME_DATA/android-home" \
  "$AVD_HOME" \
  "$RUNTIME_DATA/adb-home" \
  "$RUNTIME_DATA/userdata"
: >"$RESULTS"

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_USER_HOME="$RUNTIME_DATA/android-home"
export ANDROID_AVD_HOME="$AVD_HOME"
export HOME="$RUNTIME_DATA/adb-home"
export ANDROID_ADB_SERVER_PORT="$ADB_SERVER_PORT"
export ADB_SERVER_SOCKET="tcp:127.0.0.1:$ADB_SERVER_PORT"

adb_private() {
  "$ADB" -P "$ADB_SERVER_PORT" -s "$SERIAL" "$@"
}

cleanup() {
  if [[ -n "${PID:-}" ]] && kill -0 "$PID" >/dev/null 2>&1; then
    adb_private emu kill >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

now_ns() {
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC \
    -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1e9'
}

wait_for_emulator_boot() {
  local pid="$1"
  local attempt
  for attempt in $(seq 1 180); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
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

"$ADB" -P "$ADB_SERVER_PORT" kill-server >/dev/null 2>&1 || true
"$ADB" -P "$ADB_SERVER_PORT" start-server >/dev/null

MARKER="greenhouse-soak-$(date +%s)"
EMULATOR_ARGS=(
  -port "$EMULATOR_PORT"
  -accel on
  -gpu host
  -no-window
  -no-boot-anim
  -no-snapshot
)
if [[ -n "$SYSTEM_IMAGE_DIR" ]]; then
  if [[ ! -f "$SYSTEM_IMAGE_DIR/system.img" \
      || ! -f "$SYSTEM_IMAGE_DIR/userdata.img" \
      || ! -f "$SYSTEM_IMAGE_DIR/kernel-ranchu" \
      || ! -f "$SYSTEM_IMAGE_DIR/ramdisk.img" \
      || ! -f "$SYSTEM_IMAGE_DIR/vendor.img" ]]; then
    echo "Community Runtime images are incomplete under $SYSTEM_IMAGE_DIR." >&2
    exit 69
  fi
  EMULATOR_ARGS=(
    -sysdir "$SYSTEM_IMAGE_DIR"
    -data "$RUNTIME_DATA/userdata/userdata-qemu.img"
    -initdata "$SYSTEM_IMAGE_DIR/userdata.img"
    "${EMULATOR_ARGS[@]}"
  )
else
  EMULATOR_ARGS=(-avd "$AVD_NAME" "${EMULATOR_ARGS[@]}")
fi

for cycle in $(seq 1 "$CYCLES"); do
  START_NS="$(now_ns)"
  LOG="$ARTIFACT_DIR/emulator-$cycle.log"
  "$EMULATOR" \
    "${EMULATOR_ARGS[@]}" \
    >"$LOG" 2>&1 &
  PID=$!
  STATUS="boot-timeout"

  if wait_for_emulator_boot "$PID"; then
    STATUS="ready"
  else
    wait_status=$?
    if [[ "$wait_status" == "2" ]]; then
      STATUS="emulator-exited"
    fi
  fi

  PERSISTED=false
  if [[ "$STATUS" == "ready" ]]; then
    if [[ "$cycle" == "1" ]]; then
      adb_private shell \
        "printf '%s' '$MARKER' > /data/local/tmp/greenhouse-soak-marker && sync"
    fi
    if [[ "$(adb_private shell cat /data/local/tmp/greenhouse-soak-marker 2>/dev/null | tr -d '\r')" == "$MARKER" ]]; then
      PERSISTED=true
    fi
  fi

  END_NS="$(now_ns)"
  python3 - "$cycle" "$STATUS" "$PERSISTED" "$START_NS" "$END_NS" >>"$RESULTS" <<'PY'
import json
import sys

print(
    json.dumps(
        {
            "cycle": int(sys.argv[1]),
            "status": sys.argv[2],
            "persistenceVerified": sys.argv[3] == "true",
            "bootMilliseconds": (int(sys.argv[5]) - int(sys.argv[4])) / 1_000_000,
        },
        sort_keys=True,
    )
)
PY

  adb_private emu kill >/dev/null 2>&1 || true
  wait "$PID" >/dev/null 2>&1 || true
  PID=""

  if [[ "$STATUS" != "ready" || "$PERSISTED" != "true" ]]; then
    echo "lifecycle soak failed at cycle $cycle ($STATUS, persistence=$PERSISTED)" >&2
    exit 70
  fi
done

python3 - "$RESULTS" "$ARTIFACT_DIR/report.json" <<'PY'
import json
import pathlib
import statistics
import sys

rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
durations = [row["bootMilliseconds"] for row in rows]
report = {
    "schemaVersion": 1,
    "cyclesRequested": len(rows),
    "cyclesPassed": sum(row["status"] == "ready" for row in rows),
    "persistencePassed": all(row["persistenceVerified"] for row in rows),
    "meanBootMilliseconds": statistics.fmean(durations),
    "maximumBootMilliseconds": max(durations),
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY

python3 -m json.tool "$ARTIFACT_DIR/report.json" >/dev/null
cat "$ARTIFACT_DIR/report.json"
