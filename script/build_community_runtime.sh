#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "The Android guest must be built on Linux." >&2
  echo "Use fetch_community_runtime.sh on macOS to verify the package supply." >&2
  exit 69
fi

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/dedicated-lineage-worktree" >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/guest/community-runtime/runtime-lock.json"
ANDROID_ROOT="$1"

command -v repo >/dev/null || {
  echo "Android repo tool is required." >&2
  exit 69
}

mkdir -p "$ANDROID_ROOT"
ANDROID_ROOT="$(cd "$ANDROID_ROOT" && pwd)"

AVAILABLE_KIB="$(df -Pk "$ANDROID_ROOT" | awk 'NR == 2 {print $4}')"
REQUIRED_KIB=$((300 * 1024 * 1024))
if (( AVAILABLE_KIB < REQUIRED_KIB )); then
  echo "At least 300 GiB free is required for the LineageOS worktree." >&2
  exit 70
fi

MANIFEST_REPOSITORY="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["android"]["manifestRepository"])' \
    "$LOCK_FILE"
)"
MANIFEST_BRANCH="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["android"]["manifestBranch"])' \
    "$LOCK_FILE"
)"
MANIFEST_REVISION="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["android"]["manifestRevision"])' \
    "$LOCK_FILE"
)"

cd "$ANDROID_ROOT"
repo init -u "$MANIFEST_REPOSITORY" -b "$MANIFEST_BRANCH"
git -C .repo/manifests fetch --depth=1 origin "$MANIFEST_REVISION"
git -C .repo/manifests checkout --detach "$MANIFEST_REVISION"

mkdir -p .repo/local_manifests
cp "$ROOT_DIR/guest/community-runtime/local-manifests/greenhouse.xml" \
  .repo/local_manifests/greenhouse.xml

repo sync -c -j"${GREENHOUSE_SYNC_JOBS:-8}" --fail-fast
"$ROOT_DIR/script/fetch_community_runtime.sh" --prepare-tree "$ANDROID_ROOT"

mkdir -p "$ROOT_DIR/artifacts/community-runtime/manifests"
repo manifest -r -o \
  "$ROOT_DIR/artifacts/community-runtime/manifests/lineage-23.2-revision-locked.xml"

export WITH_GMS=true
source build/envsetup.sh
lunch greenhouse_sdk_phone_arm64-userdebug
m -j"${GREENHOUSE_BUILD_JOBS:-$(nproc)}"

mkdir -p "$ROOT_DIR/artifacts/community-runtime/build-metadata"
cp "$OUT/build_number.txt" \
  "$ROOT_DIR/artifacts/community-runtime/build-metadata/build-number.txt" 2>/dev/null || true
grep -Rhs '^PLATFORM_SECURITY_PATCH *:=' build/make/core vendor/lineage 2>/dev/null \
  >"$ROOT_DIR/artifacts/community-runtime/build-metadata/security-patch.txt" || true

IMAGE_DIR="$ROOT_DIR/artifacts/community-runtime/images"
mkdir -p "$IMAGE_DIR"
for image in \
  boot.img \
  dtb.img \
  encryptionkey.img \
  init_boot.img \
  kernel-ranchu \
  product.img \
  ramdisk.img \
  system.img \
  system_ext.img \
  userdata.img \
  vbmeta.img \
  vbmeta_system.img \
  vendor.img \
  vendor_boot.img; do
  if [[ -f "$OUT/$image" ]]; then
    cp "$OUT/$image" "$IMAGE_DIR/$image"
  fi
done

for required_image in \
  kernel-ranchu \
  ramdisk.img \
  system.img \
  userdata.img \
  vendor.img; do
  if [[ ! -f "$IMAGE_DIR/$required_image" ]]; then
    echo "Required Ranchu image was not produced: $required_image" >&2
    exit 70
  fi
done

python3 - "$IMAGE_DIR" \
  "$ROOT_DIR/artifacts/community-runtime/build-metadata/runtime-images.json" <<'PY'
import hashlib
import json
import pathlib
import sys

image_dir = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
images = []
for path in sorted(image_dir.iterdir()):
    if not path.is_file():
        continue
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    images.append(
        {
            "name": path.name,
            "size": path.stat().st_size,
            "sha256": digest.hexdigest(),
        }
    )
manifest_path.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "product": "greenhouse_sdk_phone_arm64",
            "userdataPolicy": "separate-persistent-image",
            "images": images,
        },
        indent=2,
        sort_keys=True,
    )
    + "\n"
)
PY

echo "community runtime build completed: $OUT"
echo "emulator image directory: $IMAGE_DIR"
