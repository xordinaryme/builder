#!/bin/bash
chk() {
df -h
free -h
lscpu
}
echo "Checking System Configuration"
chk

sync() {
repo init --depth=1 --no-repo-verify -u $ROMREPO
git clone $LOCALMANIFEST .repo/local_manifests
repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle -j$(nproc --all)
}
echo "Syncing Rom & Device Sources"
sync
