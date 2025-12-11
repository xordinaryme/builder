#!/bin/bash


rm -rf hardware/xiaomi
git clone --depth=1 https://github.com/xordinaryme/hardware_xiaomi -b thirteen hardware/xiaomi

rm -rf vendor/aosp
git clone --depth=1 https://github.com/xordinaryme/vendor_aosp -b thirteen-plus vendor/aosp

echo "Device requirements set successfully."
