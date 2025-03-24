#!/bin/bash

rom_upload() {
cd ~/
curl --upload-file ./out/target/product/$DEVICE/lineage*.zip https://free.keep.sh > link.txt && cat link.txt
curl --upload-file ./out/target/product/$DEVICE/boot.img https://free.keep.sh > link1.txt && cat link1.txt
}
echo "Uploading Rom & Boot From /Out"
rom_upload
