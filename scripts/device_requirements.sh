#!/bin/bash


rm -rf vendor/lineage
git clone --depth=1 https://github.com/ordinary-topaz-lab/vendor_lineage -b thirteen-plus vendor/lineage

echo "Device requirements set successfully."
