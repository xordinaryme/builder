#!/bin/bash

set_requirements() {
rm -rf vendor/aosp
git clone --depth=1 https://github.com/ordinary-topaz-lab/vendor_aosp_legacy -b thirteen vendor/aosp
}

set_requirements
echo "Device requirements set successfully."
