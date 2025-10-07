#!/bin/bash

# Device tree
rm -rf device/xiaomi/tapas
git clone --depth=1 https://github.com/ordinary-topaz-lab/android_device_xiaomi_tapas -b 13 device/xiaomi/tapas
rm -rf device/xiaomi/tapas-kernel
git clone --depth=1 https://github.com/ordinary-topaz-lab/android_device_xiaomi_tapas-kernel -b 13 device/xiaomi/tapas-kernel
rm -rf vendor/xiaomi/tapas
git clone --depth=1 https://github.com/ordinary-topaz-lab/proprietary_vendor_xiaomi_tapas -b 13 vendor/xiaomi/tapas
rm -rf hardware/qcom-caf/sm6225
git clone --depth=1 https://github.com/ordinary-topaz-lab/hardware_qcom-caf_sm6225 -b main hardware/qcom-caf/sm6225

# Required
rm -rf vendor/aosp
git clone --depth=1 https://github.com/ordinary-topaz-lab/vendor_aosp_legacy -b thirteen-plus vendor/aosp
rm -rf hardware/xiaomi
git clone --depth=1 https://github.com/ordinary-topaz-lab/hardware_xiaomi -b 13 hardware/xiaomi


echo "Device requirements set successfully."
