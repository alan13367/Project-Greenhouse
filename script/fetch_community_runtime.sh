#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/guest/community-runtime/runtime-lock.json"
DOWNLOAD_DIR="$ROOT_DIR/artifacts/community-runtime/downloads"
STAGING_ROOT="$ROOT_DIR/artifacts/community-runtime/staging"
PREPARE_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare-tree)
      PREPARE_ROOT="${2:?--prepare-tree requires an Android source root}"
      shift 2
      ;;
    *)
      echo "usage: $0 [--prepare-tree /path/to/android-source]" >&2
      exit 64
      ;;
  esac
done

mkdir -p "$DOWNLOAD_DIR"

python3 - "$LOCK_FILE" "$DOWNLOAD_DIR" <<'PY'
import hashlib
import json
import pathlib
import sys
import urllib.parse
import urllib.request

lock = json.loads(pathlib.Path(sys.argv[1]).read_text())
download_dir = pathlib.Path(sys.argv[2])

for package in lock["packages"]:
    filename = pathlib.Path(urllib.parse.urlparse(package["url"]).path).name
    destination = download_dir / filename

    if destination.is_file():
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        if digest == package["sha256"]:
            print(f"verified cached {filename}")
            continue
        destination.unlink()

    temporary = destination.with_suffix(destination.suffix + ".partial")
    temporary.unlink(missing_ok=True)
    print(f"downloading {package['module']} {package['version']}")
    request = urllib.request.Request(
        package["url"],
        headers={"User-Agent": "Greenhouse-Community-Runtime/1"},
    )
    with urllib.request.urlopen(request) as response, temporary.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)

    digest = hashlib.sha256(temporary.read_bytes()).hexdigest()
    if digest != package["sha256"]:
        temporary.unlink(missing_ok=True)
        raise SystemExit(
            f"SHA-256 mismatch for {filename}: {digest} != {package['sha256']}"
        )
    temporary.replace(destination)
    print(f"verified {filename}")
PY

"$ROOT_DIR/script/verify_community_runtime.sh" --downloads

if [[ -n "$PREPARE_ROOT" ]]; then
  STAGING_ROOT="$(cd "$PREPARE_ROOT" && pwd)"
else
  mkdir -p "$STAGING_ROOT"
fi

VENDOR_DIR="$STAGING_ROOT/vendor/partner_gms"
INTEGRATION_REPOSITORY="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["integration"]["repository"])' \
    "$LOCK_FILE"
)"
INTEGRATION_REVISION="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["integration"]["revision"])' \
    "$LOCK_FILE"
)"

if ! git -C "$VENDOR_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  rm -rf "$VENDOR_DIR"
  mkdir -p "$(dirname "$VENDOR_DIR")"
  git clone --filter=blob:none --no-checkout "$INTEGRATION_REPOSITORY" "$VENDOR_DIR"
fi

git -C "$VENDOR_DIR" fetch --depth=1 origin "$INTEGRATION_REVISION"
git -C "$VENDOR_DIR" checkout --detach "$INTEGRATION_REVISION"

python3 - "$LOCK_FILE" "$VENDOR_DIR" <<'PY'
import hashlib
import json
import pathlib
import sys

lock = json.loads(pathlib.Path(sys.argv[1]).read_text())
repository_file = (
    pathlib.Path(sys.argv[2])
    / "additional_repos.xml"
    / "additional_repos.json"
)
repositories = json.loads(repository_file.read_text())
microg = next(
    repository
    for repository in repositories
    if repository["address"] == "https://microg.org/fdroid/repo"
)
fingerprint = hashlib.sha256(bytes.fromhex(microg["certificate"])).hexdigest().upper()
expected = lock["integration"]["fdroidRepositoryFingerprintSha256"]
if fingerprint != expected:
    raise SystemExit(
        f"microG F-Droid repository fingerprint mismatch: {fingerprint} != {expected}"
    )
print(f"verified microG F-Droid repository fingerprint {fingerprint}")
PY

PRODUCT_DIR="$STAGING_ROOT/vendor/greenhouse/product"
rm -rf "$PRODUCT_DIR"
mkdir -p "$PRODUCT_DIR"
cp "$ROOT_DIR/guest/community-runtime/product/AndroidProducts.mk" "$PRODUCT_DIR/"
cp "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk" "$PRODUCT_DIR/"

AGENT_DIR="$STAGING_ROOT/packages/apps/GreenhouseAppWindowAgent"
rm -rf "$AGENT_DIR"
mkdir -p "$(dirname "$AGENT_DIR")"
cp -R "$ROOT_DIR/guest/app-window-agent" "$AGENT_DIR"

python3 - "$LOCK_FILE" "$DOWNLOAD_DIR" "$VENDOR_DIR" <<'PY'
import json
import pathlib
import shutil
import sys
import urllib.parse

lock = json.loads(pathlib.Path(sys.argv[1]).read_text())
download_dir = pathlib.Path(sys.argv[2])
vendor_dir = pathlib.Path(sys.argv[3])

for package in lock["packages"]:
    filename = pathlib.Path(urllib.parse.urlparse(package["url"]).path).name
    source = download_dir / filename
    destination = vendor_dir / package["destination"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    print(f"staged {package['module']} -> {destination}")
PY

echo "community runtime tree prepared at $STAGING_ROOT"
