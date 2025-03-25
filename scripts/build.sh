#!/bin/bash
build() {
source build/envsetup.sh || . build/envsetup.sh
lunch $MAKEFILENAME-$VARIENT
#export SKIP_ABI_CHECKS=true
#export SKIP_API_CHECKS=true
#export ALLOW_MISSING_DEPENDENCIES=true
#export PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS=false
$EXTRACMD
$TARGET -j$(nproc --all) & sleep 95m
}
echo "Initializing Build System"
build
