#!/bin/bash


rm -rf hardware/qcom-caf/common
git clone --depth=1 https://github.com/xordinary/android_hardware_qcom-caf_common -b lineage-23.0 hardware/qcom--caf/common

echo "Device requirements set successfully."
