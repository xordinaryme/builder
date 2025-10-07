#!/bin/bash

sync_repo() {
    repo init --depth=1 --no-repo-verify --git-lfs -u $ROMREPO -g default,-mips,-darwin,-notdefault
    rm -rf .repo/local_manifests
    git clone $LOCALMANIFEST .repo/local_manifests
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all)
}

echo "Syncing ROM & Device Sources"
sync_repo
