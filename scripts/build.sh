#!/bin/bash
set -e

ROM_NAME="${MAKEFILENAME%%_*}"
CCACHE_DIR="$HOME/.ccache"
CCACHE_TAR="${ROM_NAME}.ccache.tar.gz"
CCACHE_COPY_DIR="$HOME/ccache_copy"
SAFE_TIME=5760
LOG_FILE="build.log"
OTA_ZIP="${OUT_DIR}/target/product/${DEVICE_CODENAME}/*.zip"

export LC_ALL=C
export TARGET_NO_KERNEL_OVERRIDE=true
export TARGET_NO_KERNEL=true
export TARGET_FORCE_PREBUILT_KERNEL=true
export TARGET_KERNEL_SOURCE=device/xiaomi/tapas-kernel/kernel-headers
export TARGET_KERNEL_VERSION=5.15

cleanup() {
    kill "$TIMER_PID" 2>/dev/null || true
    rm -rf "$CCACHE_COPY_DIR" "$CCACHE_TAR"
}
trap cleanup EXIT

setup_ccache() {
    export USE_CCACHE=1
    ccache -M 20G
    ccache -z
}

download_ccache() {
    response=$(curl -s -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/user/files") || return 1
    ccache_file_id=$(echo "$response" | jq -r --arg CCACHE_TAR "$CCACHE_TAR" \
        '[.files[] | select(.name | test("^" + $CCACHE_TAR + "$"))] | sort_by(.date_upload) | last | .id')
    [ -z "$ccache_file_id" ] || [ "$ccache_file_id" = "null" ] && return 1
    curl -L -o "$CCACHE_TAR" "https://pixeldrain.com/api/file/$ccache_file_id?download" || return 1
    mkdir -p "$CCACHE_DIR"
    tar -xzf "$CCACHE_TAR" -C "$CCACHE_DIR"
    rm -f "$CCACHE_TAR"
}

compress_and_upload_ccache() {
    mkdir -p "$CCACHE_COPY_DIR"
    rsync -a --delete "$CCACHE_DIR/" "$CCACHE_COPY_DIR/" || cp -a "$CCACHE_DIR/." "$CCACHE_COPY_DIR/"
    tar -czf "$CCACHE_TAR" -C "$CCACHE_COPY_DIR" . || return 1
    response=$(curl -s -X POST -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$CCACHE_TAR" "https://pixeldrain.com/api/file") || return 1
    file_id=$(echo "$response" | jq -r '.id')
    [ -n "$file_id" ] && [ "$file_id" != "null" ] && echo "Uploaded: https://pixeldrain.com/u/$file_id"
}

upload_ota() {
    ota_file=$(find "out/target/product/${DEVICE_CODENAME}" -name "PixelExperience*.zip" -type f | head -n 1)
    [ -z "$ota_file" ] && return 1
    response=$(curl -s -X POST -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$ota_file" "https://pixeldrain.com/api/file") || return 1
    file_id=$(echo "$response" | jq -r '.id')
    [ -n "$file_id" ] && [ "$file_id" != "null" ] && echo "OTA ZIP uploaded: https://pixeldrain.com/u/$file_id"
}

# monitor_time_with_logs() {
#    local start_time=$(date +%s)
#    local last_display_time=$start_time
#    while true; do
#        local current_time=$(date +%s)
#        local elapsed=$((current_time - start_time))
#        local remaining=$((SAFE_TIME - elapsed))
#        (( remaining <= 0 )) && { compress_and_upload_ccache; exit 0; }
#        if (( current_time - last_display_time >= 300 )); then
#            echo -ne "\r$(date): Elapsed: ${elapsed}s | Remaining: ${remaining}s"
#            tail -n 10 "$LOG_FILE"
#            last_display_time=$current_time
#        fi
#        sleep 1
#    done
# }

build() {
    . build/envsetup.sh
    lunch "$MAKEFILENAME-$VARIANT" || exit 1
    $TARGET -j8
}

echo "ROM: $MAKEFILENAME"
echo "Device: $DEVICE_CODENAME"
echo "Variant: $VARIANT"
# : > "$LOG_FILE"
# monitor_time_with_logs &
# TIMER_PID=$!
setup_ccache
download_ccache || echo "No ccache found"
build
upload_ota
compress_and_upload_ccache
echo "Build complete."
