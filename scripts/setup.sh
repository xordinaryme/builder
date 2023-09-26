#!/bin/bash
setup() {
sudo apt update &&sudo apt install pigz wget jq -y
wget https://github.com/akhilnarang/scripts/raw/master/setup/android_build_env.sh
chmod +rwx android_build_env.sh
./android_build_env.sh || source android_build_env.sh
rm -rf android_build_env.sh
}
echo "Setting Up AOSP Build Environment"
setup

ccache() {
cd /tmp
time aria2c $LINK -x16 -s50 || echo "No ccache link provided, build will fail due to time limit"
time tar xf ccache.tar.gz
}
echo "Downloading CCACHE"
ccache

workrepo() {
mkdir -p ~/work
cd ~/ && cd ~/work
}
echo "Working Directory Created Successfully"
workrepo

