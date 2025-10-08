#!/bin/bash


rm -rf vendor/lineage
git clone --depth=1 https://github.com/ordinary-topaz-lab/android_vendor_lineage -b lineage-20.0 vendor/lineage

echo "Device requirements set successfully."
