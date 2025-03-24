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
repo sync --current-branch --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$( nproc --all )
rm -rf hardware/qcom-caf/sm8250
}
echo "Syncing Rom & Device Sources"
sync
