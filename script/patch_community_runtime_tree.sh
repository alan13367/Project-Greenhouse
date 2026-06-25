#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/android-source" >&2
  exit 64
fi

ANDROID_ROOT="$(cd "$1" && pwd)"

python3 - "$ANDROID_ROOT" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def remove_lineage_apn_package(relative_path: str) -> None:
    path = root / relative_path
    text = path.read_text()
    block = "# World APN list\nPRODUCT_PACKAGES += \\\n    apns-conf.xml\n\n"
    replacement = (
        "# World APN list\n"
        "# Greenhouse keeps the inherited AOSP product APN copy to avoid a\n"
        "# duplicate install rule with Lineage's generated apns-conf.xml module.\n\n"
    )
    if block in text:
        path.write_text(text.replace(block, replacement, 1))
        print(f"{relative_path}: removed duplicate apns-conf.xml package")
    elif any(line.strip() == "apns-conf.xml" for line in text.splitlines()):
        raise SystemExit(f"{relative_path}: unexpected apns-conf.xml package form")
    else:
        print(f"{relative_path}: duplicate apns-conf.xml package already absent")


def remove_aosp_product_apn_copy() -> None:
    relative_path = "build/make/target/product/aosp_product.mk"
    path = root / relative_path
    text = path.read_text()
    block = (
        "# Telephony:\n"
        "#   Provide a APN configuration to GSI product\n"
        "ifeq ($(LINEAGE_BUILD),)\n"
        "PRODUCT_COPY_FILES += \\\n"
        "    device/sample/etc/apns-full-conf.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/apns-conf.xml\n"
        "endif\n"
    )
    replacement = (
        "# Telephony:\n"
        "# Greenhouse does not install the AOSP product APN copy because the\n"
        "# emulator vendor APN copy is already provided by Goldfish/Ranchu.\n"
    )
    if block in text:
        path.write_text(text.replace(block, replacement, 1))
        print(f"{relative_path}: removed duplicate product apns-conf.xml copy")
    elif "device/sample/etc/apns-full-conf.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/apns-conf.xml" in text:
        raise SystemExit(f"{relative_path}: unexpected product apns-conf.xml copy form")
    else:
        print(f"{relative_path}: duplicate product apns-conf.xml copy already absent")


def ensure_vendor_available(relative_path: str, module_name: str) -> None:
    path = root / relative_path
    lines = path.read_text().splitlines()

    name_index = next(
        index
        for index, line in enumerate(lines)
        if line.strip() == f'name: "{module_name}",'
    )
    block_start = name_index
    while block_start >= 0 and not lines[block_start].strip().endswith("{"):
        block_start -= 1
    block_end = name_index
    while block_end < len(lines) and lines[block_end].strip() != "}":
        block_end += 1
    if block_start < 0 or block_end >= len(lines):
        raise SystemExit(f"could not find complete module block for {module_name}")

    if any(line.strip() == "vendor_available: true," for line in lines[block_start:block_end]):
        print(f"{module_name}: vendor_available already set")
        return

    insert_after = next(
        index
        for index in range(name_index + 1, block_end)
        if lines[index].strip() == "host_supported: true,"
    )
    lines.insert(insert_after + 1, "    vendor_available: true,")
    path.write_text("\n".join(lines) + "\n")
    print(f"{module_name}: enabled vendor_available")


ensure_vendor_available("external/skia/Android.bp", "libskia_skcms")
ensure_vendor_available("external/google-highway/Android.bp", "libhwy")
ensure_vendor_available("external/XMP-Toolkit-SDK/Android.bp", "zuid_md5")
ensure_vendor_available("external/XMP-Toolkit-SDK/Android.bp", "xmp_toolkit_sdk")
remove_lineage_apn_package("vendor/lineage/config/telephony.mk")
remove_lineage_apn_package("vendor/lineage/config/data_only.mk")
remove_aosp_product_apn_copy()
PY
