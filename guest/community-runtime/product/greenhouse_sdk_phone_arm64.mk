#
# SPDX-License-Identifier: Apache-2.0
#

# The Android Emulator's ARM64 Goldfish/Ranchu hardware target. This inherits
# the gfxstream guest graphics stack and kernel-ranchu packaging used by stock
# ARM64 AVDs instead of the Cuttlefish device model.
$(call inherit-product, vendor/lineage/build/target/product/lineage_sdk_phone_arm64.mk)
$(call inherit-product, vendor/partner_gms/products/gms_64bit_only.mk)

TARGET_NO_KERNEL_OVERRIDE := true

GREENHOUSE_LINEAGE_SOONG_EXPORTS := \
    KERNEL_ARCH \
    KERNEL_BUILD_OUT_PREFIX \
    KERNEL_CROSS_COMPILE \
    KERNEL_MAKE_CMD \
    KERNEL_MAKE_FLAGS \
    KERNEL_PATH \
    PATH_OVERRIDE_SOONG \
    TARGET_KERNEL_CONFIG \
    TARGET_KERNEL_SOURCE \
    TARGET_KERNEL_PLATFORM_TARGET \
    TARGET_PREBUILT_KERNEL_HEADERS
$(call add_soong_config_namespace,lineageVarsPlugin)
$(foreach v,$(GREENHOUSE_LINEAGE_SOONG_EXPORTS),\
    $(eval $(call add_soong_config_var,lineageVarsPlugin,$(v))))

PRODUCT_NAME := greenhouse_sdk_phone_arm64
PRODUCT_BRAND := Greenhouse
PRODUCT_MODEL := Greenhouse Community Runtime
PRODUCT_MANUFACTURER := Greenhouse

PRODUCT_COPY_FILES := $(filter-out \
    device/sample/etc/apns-full-conf.xml:%/etc/apns-conf.xml \
    device/sample/etc/apns-full-conf.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/apns-conf.xml \
    device/sample/etc/apns-full-conf.xml:product/etc/apns-conf.xml, \
    $(PRODUCT_COPY_FILES))

PRODUCT_PACKAGES += GreenhouseAppWindowAgent

PRODUCT_PRODUCT_PROPERTIES += \
    ro.greenhouse.runtime.channel=community \
    ro.greenhouse.virtual_hardware=ranchu \
    ro.greenhouse.graphics.transport=gfxstream \
    ro.greenhouse.google_services.provider=microg \
    ro.greenhouse.official_google_play=false

# The app-window agent is platform-signed and only accepts connections through
# a localabstract socket reached over Greenhouse's private ADB server.
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.greenhouse.app_window_agent.socket=greenhouse-app-window
