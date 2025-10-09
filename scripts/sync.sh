#!/bin/bash

sync_repo() {
    repo init -u https://github.com/AndroidOne-Experience/manifest.git -b 15 --no-repo-verify --depth=1 --git-lfs
    rm -rf .repo/local_manifests
    git clone $LOCALMANIFEST .repo/local_manifests
    repo sync -c -j8 --force-sync --no-clone-bundle --no-tags
}

echo "Syncing ROM & Device Sources"
sync_repo
