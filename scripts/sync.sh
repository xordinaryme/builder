#!/bin/bash

chk() {
    df -h
    free -h
    lscpu
}

echo "Checking System Configuration"
chk

sync_repo() {
    if [[ -z "$ROMREPO" || -z "$LOCALMANIFEST" ]]; then
        echo "Error: ROMREPO or LOCALMANIFEST is not set."
        exit 1
    fi

    repo init --depth=1 --no-repo-verify -u "$ROMREPO"
    git clone "$LOCALMANIFEST" .repo/local_manifests
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all)
}

echo "Syncing ROM & Device Sources"
sync_repo
