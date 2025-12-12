#!/bin/bash


# rm -rf hardware/xiaomi
# git clone --depth=1 https://github.com/xordinaryme/hardware_xiaomi -b thirteen hardware/xiaomi

rm -rf vendor/lineage
git clone --depth=1 https://github.com/topnotchfreaks/android_vendor_lineage -b lineage-20.0 vendor/lineage

echo "Device requirements set successfully."
