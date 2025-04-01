#!/bin/bash

chk() {
    df -h
    free -h
    lscpu
}

echo "Checking System Configuration"
chk

sync_repo() {
    repo init --depth=1 --no-repo-verify -u $ROMREPO --git-lfs
    rm -rf .repo/local_manifests
    git clone $LOCALMANIFEST .repo/local_manifests
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j8
}

echo "Syncing ROM & Device Sources"
sync_repo
