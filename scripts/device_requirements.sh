#!/bin/bash

rm -rf vendor/aosp
git clone --depth=1 https://github.com/ordinary-topaz-lab/android_vendor_aosp_legacy -b 13 vendor/aosp
rm -rf hardware/xiaomi
git clone --depth=1 https://github.com/ordinary-topaz-lab/hardware_xiaomi -b 13 hardware/xiaomi

echo "Device requirements set successfully."
