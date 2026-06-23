#
# SPDX-License-Identifier: Apache-2.0
#

# The Android Emulator's ARM64 Goldfish/Ranchu hardware target. This inherits
# the gfxstream guest graphics stack and kernel-ranchu packaging used by stock
# ARM64 AVDs instead of the Cuttlefish device model.
$(call inherit-product, vendor/lineage/build/target/product/lineage_sdk_phone_arm64.mk)
$(call inherit-product, vendor/partner_gms/products/gms_64bit_only.mk)

PRODUCT_NAME := greenhouse_sdk_phone_arm64
PRODUCT_BRAND := Greenhouse
PRODUCT_MODEL := Greenhouse Community Runtime
PRODUCT_MANUFACTURER := Greenhouse

PRODUCT_PACKAGES += GreenhouseAppWindowAgent

PRODUCT_SYSTEM_PROPERTIES += \
    ro.greenhouse.runtime.channel=community \
    ro.greenhouse.virtual_hardware=ranchu \
    ro.greenhouse.graphics.transport=gfxstream \
    ro.greenhouse.google_services.provider=microg \
    ro.greenhouse.official_google_play=false

# The app-window agent is platform-signed and only accepts connections through
# a localabstract socket reached over Greenhouse's private ADB server.
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.greenhouse.app_window_agent.socket=greenhouse-app-window
