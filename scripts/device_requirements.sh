#!/bin/bash

set_requirements() {
rm -rf vendor/crdroid
git clone --depth=1 https://github.com/passive-development/vendor_lineage -b lineage-20.0 vendor/crdroid
}

set_requirements
echo "Device requirements set successfully."
