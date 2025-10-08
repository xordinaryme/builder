#!/bin/bash

sudo add-apt-repository universe

sudo apt update && sudo apt install -y \
  bc bison build-essential ccache curl \
  flex g++-multilib gcc-multilib git git-lfs \
  gnupg gperf imagemagick lib32ncurses-dev lib32readline-dev \
  lib32z1-dev liblz4-tool libncurses6 libncurses-dev \
  libsdl1.2-dev libssl-dev libwxgtk3.2-dev libxml2 libxml2-utils \
  lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev \
  git repo wget \
  libtinfo5 libncurses5

sudo apt upgrade -y

echo "Setting Up AOSP Build Environment"
