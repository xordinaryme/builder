#!/bin/bash

sudo apt update && sudo apt install \
 bc bison build-essential ccache curl \
 flex g++-multilib gcc-multilib git git-lfs \
 gnupg gperf imagemagick lib32ncurses5-dev lib32readline-dev \
 lib32z1-dev liblz4-tool libncurses5 libncurses5-dev \
 libsdl1.2-dev libssl-dev libwxgtk3.0-gtk3-dev libxml2 libxml2-utils \
 lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev

sudo apt upgrade -y
    
echo "Setting Up AOSP Build Environment"
