#!/bin/bash
build() {
source ./build/envsetup.sh #this command sometimes do the jobs
. build/envsetup.sh  #sometimes this one do the jobs, it depends on system itself. Better use both
bash device/xiaomi/fleur/prebuilts/vendor.sh
lunch $MAKEFILENAME_$DEVICE-$VARIENT
export SKIP_ABI_CHECKS=true
export SKIP_API_CHECKS=true
export ALLOW_MISSING_DEPENDENCIES=true
$TARGET -j$(nproc --all) || curl --upload-file ./out/error.log https://free.keep.sh > link.txt && cat link.txt
}
echo "Initializing Build System"
build
