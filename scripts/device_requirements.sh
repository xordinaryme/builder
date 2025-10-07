#!/bin/bash

rm -rf vendor/crdroid
git clone --depth=1 https://github.com/ordinary-topaz-lab/android_vendor_crdroid -b 13.0 vendor/crdroid
# rm -rf hardware/xiaomi
# git clone --depth=1 https://github.com/ordinary-topaz-lab/hardware_xiaomi -b 13 hardware/xiaomi

echo "Device requirements set successfully."
