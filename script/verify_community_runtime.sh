#!/usr/bin/env bash
# Validate the pinned Community Runtime supply lock and product definition.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/guest/community-runtime/runtime-lock.json"
SCHEMA_FILE="$ROOT_DIR/runtime/schemas/community-runtime-lock.schema.json"
DOWNLOAD_DIR="$ROOT_DIR/artifacts/community-runtime/downloads"
VERIFY_DOWNLOADS=false

if [[ "${1:-}" == "--downloads" ]]; then
  VERIFY_DOWNLOADS=true
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--downloads]" >&2
  exit 64
fi

python3 -m json.tool "$LOCK_FILE" >/dev/null
python3 -m json.tool "$SCHEMA_FILE" >/dev/null

python3 - "$LOCK_FILE" "$DOWNLOAD_DIR" "$VERIFY_DOWNLOADS" <<'PY'
import hashlib
import json
import pathlib
import re
import sys
import urllib.parse

lock_path = pathlib.Path(sys.argv[1])
download_dir = pathlib.Path(sys.argv[2])
verify_downloads = sys.argv[3] == "true"
lock = json.loads(lock_path.read_text())

if lock.get("schemaVersion") != 1:
    raise SystemExit("community runtime lock must use schemaVersion 1")

git_revision = re.compile(r"^[0-9a-f]{40}$")
sha256 = re.compile(r"^[0-9a-f]{64}$")

for label, revision in (
    ("Android manifest", lock["android"]["manifestRevision"]),
    ("microG integration", lock["integration"]["revision"]),
):
    if not git_revision.fullmatch(revision):
        raise SystemExit(f"{label} revision is not a full 40-character commit")

if lock["integration"]["officialGooglePlayIncluded"] is not False:
    raise SystemExit("the community runtime must not claim official Google Play")
if not re.fullmatch(
    r"[0-9A-F]{64}",
    lock["integration"]["fdroidRepositoryFingerprintSha256"],
):
    raise SystemExit("microG F-Droid repository fingerprint is invalid")

seen_modules = set()
seen_destinations = set()
for package in lock["packages"]:
    module = package["module"]
    destination = package["destination"]
    if module in seen_modules or destination in seen_destinations:
        raise SystemExit(f"duplicate package module or destination: {module}")
    seen_modules.add(module)
    seen_destinations.add(destination)

    parsed = urllib.parse.urlparse(package["url"])
    if parsed.scheme != "https" or not parsed.netloc:
        raise SystemExit(f"{module} must use an HTTPS source URL")
    if not sha256.fullmatch(package["sha256"]):
        raise SystemExit(f"{module} has an invalid SHA-256")

    if verify_downloads:
        artifact = download_dir / pathlib.Path(parsed.path).name
        if not artifact.is_file():
            raise SystemExit(f"missing downloaded package: {artifact}")
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        if digest != package["sha256"]:
            raise SystemExit(
                f"SHA-256 mismatch for {artifact.name}: {digest} != {package['sha256']}"
            )

required = {
    "GmsCore",
    "FakeStore",
    "GsfProxy",
    "FDroid",
    "FDroidPrivilegedExtension",
}
if seen_modules != required:
    raise SystemExit(f"unexpected module set: {sorted(seen_modules)}")

print(
    f"community runtime lock verified: {len(seen_modules)} packages, "
    f"official Google Play disabled"
)
PY

grep -Fq 'greenhouse_sdk_phone_arm64-userdebug' \
  "$ROOT_DIR/guest/community-runtime/product/AndroidProducts.mk"
grep -Fq 'lineage_sdk_phone_arm64.mk' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'vendor/partner_gms/products/gms_64bit_only.mk' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'GreenhouseAppWindowAgent' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'graphics.transport=gfxstream' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
grep -Fq 'official_google_play=false' \
  "$ROOT_DIR/guest/community-runtime/product/greenhouse_sdk_phone_arm64.mk"
