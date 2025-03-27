#!/bin/bash

set_requirements() {
# remove source prebuilt
rm -rf device/qcom/sepolicy/vndr
rm -rf external/tinycompress
rm -rf hardware/qcom/audio
rm -rf hardware/qcom/display
rm -rf hardware/qcom/media
rm -rf vendor/qcom/opensource/arpal
rm -rf vendor/qcom/opensource/dataipa
rm -rf vendor/qcom/opensource/data-ipa-cfg-mgr
rm -rf vendor/qcom/opensource/agm
rm -rf vendor/lineage

# clone requirements for device
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/device_qcom_sepolicy_vndr -b lineage-20.0-caf-sm6225 device/qcom/sepolicy/vndr
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/external_tinycompress -b 13 external/tinycompress
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/hardware_qcom_audio -b lineage-20.0-caf-sm6225 hardware/qcom/audio
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/hardware_qcom_display -b lineage-20.0-caf-sm6225 hardware/qcom/display
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/hardware_qcom_media -b lineage-20.0-caf-sm6225 hardware/qcom/media
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/vendor_qcom_opensource_arpal -b lineage-20.0-caf-sm6225 vendor/qcom/opensource/arpal
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/vendor_qcom_opensource_dataipa -b lineage-20.0-caf-sm6225 vendor/qcom/opensource/dataipa
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/vendor_qcom_opensource_data-ipa-cfg-mgr -b lineage-20.0-caf-sm6225 vendor/qcom/opensource/data-ipa-cfg-mgr
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/vendor_qcom_opensource_agm -b lineage-20.0-caf-sm6225 vendor/qcom/opensource/agm
git clone --depth=1 https://github.com/Xiaomi-SD685-Devs/vendor_lineage -b lineage-20.0 vendor/lineage
}

set_requirements
echo "Device requirements set successfully."
