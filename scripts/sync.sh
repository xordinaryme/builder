#!/bin/bash

chk() {
    df -h
    free -h
    lscpu
}

echo "Checking System Configuration"
chk

sync_repo() {
    repo init --depth=1 --no-repo-verify -u $ROMREPO
    git clone $LOCALMANIFEST .repo/local_manifests
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all)
}

echo "Syncing ROM & Device Sources"
sync_repo
