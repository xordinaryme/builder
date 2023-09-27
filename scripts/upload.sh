#!/bin/bash
rccache() {
cd /tmp
rm ccache.tar.gz
}
echo "Removing Old CCACHE"
rccache

compress() {
time tar --use-compress-program="pigz -k -$2 " -cf $1.tar.gz $1 ccache 1
}
echo "Compressing New CCACHE"
compress

uccache() {
mkdir -p ~/.config/rclone
echo "$E" > ~/.config/rclone/rclone.conf
time rclone copy ccache.tar.gz $F -P
}
echo "Uploading CCACHE"
uccache

rom_upload() {
cd ~/
curl --upload-file ./out/target/product/$DEVICE/Sup*.zip https://free.keep.sh > link.txt && cat link.txt
curl --upload-file ./out/target/product/$DEVICE/boot.img https://free.keep.sh > link1.txt && cat link1.txt
}
echo "Uploading Rom & Boot From /Out"
rom_upload
