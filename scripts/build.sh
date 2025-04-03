#!/bin/bash
set -e

# ===== Configuration =====
# Essential Variables (should be set as env vars or defined here)
CCACHE_DIR=${HOME}/.ccache

# Derived Variables
CCACHE_COPY_DIR="$HOME/ccache_copy"
CCACHE_TAR="ccache.tar.gz"
SAFE_TIME=5760  # 1 hour and 35 minutes in seconds
LOG_FILE="build.log"
OTA_ZIP="${OUT_DIR}/target/product/${DEVICE_CODENAME}/*.zip"

# ===== 64-bit Enforcement =====
export TARGET_ARCH=arm64
export TARGET_SUPPORTS_32_BIT_APPS=false

# ===== Functions =====

# Cleanup handler
cleanup() {
    echo "Performing cleanup..."
    # Kill background processes
    kill "$TIMER_PID" 2>/dev/null || true
    # Remove temporary files
    rm -rf "$CCACHE_COPY_DIR" "$CCACHE_TAR"
}
trap cleanup EXIT

setup_ccache() {
    echo "Setting up ccache..."
    export USE_CCACHE=1
    ccache -M 50G
    ccache -z
}

download_ccache() {
    echo "Checking for existing ccache on PixelDrain..."
    response=$(curl -s -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/user/files") || return 1
    
    ccache_file_id=$(echo "$response" | jq -r '[.files[] | select(.name | contains("ccache"))] | sort_by(.date_upload) | last | .id')
    
    [ -z "$ccache_file_id" ] || [ "$ccache_file_id" = "null" ] && return 1
    
    echo "Downloading ccache (ID: $ccache_file_id)..."
    if curl -L -o "$CCACHE_TAR" "https://pixeldrain.com/api/file/$ccache_file_id?download"; then
        mkdir -p "$CCACHE_DIR"
        tar -xzf "$CCACHE_TAR" -C "$CCACHE_DIR"
        rm -f "$CCACHE_TAR"
        return 0
    else
        rm -f "$CCACHE_TAR"
        return 1
    fi
}

compress_and_upload_ccache() {
    echo "Creating safe copy of ccache..."
    mkdir -p "$CCACHE_COPY_DIR"
    rsync -a --delete "$CCACHE_DIR/" "$CCACHE_COPY_DIR/" || cp -a "$CCACHE_DIR/." "$CCACHE_COPY_DIR/"
    
    echo "Compressing ccache..."
    tar -czf "$CCACHE_TAR" -C "$CCACHE_COPY_DIR" . || return 1
    
    echo "Uploading to PixelDrain..."
    response=$(curl -s -X POST \
        -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$CCACHE_TAR" \
        "https://pixeldrain.com/api/file") || return 1
    
    file_id=$(echo "$response" | jq -r '.id')
    [ -n "$file_id" ] && [ "$file_id" != "null" ] && echo "Uploaded: https://pixeldrain.com/u/$file_id"
}

upload_ota() {
    echo "Uploading OTA ZIP..."
    ota_file=$(find "${OUT_DIR}/target/product/${DEVICE_CODENAME}" -name "*.zip" -type f | head -n 1)
    
    if [ -z "$ota_file" ]; then
        echo "No OTA ZIP file found!"
        return 1
    fi
    
    echo "Found OTA ZIP: $ota_file"
    response=$(curl -s -X POST \
        -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$ota_file" \
        "https://pixeldrain.com/api/file") || return 1
    
    file_id=$(echo "$response" | jq -r '.id')
    if [ -n "$file_id" ] && [ "$file_id" != "null" ]; then
        echo "OTA ZIP uploaded: https://pixeldrain.com/u/$file_id"
    else
        echo "Failed to upload OTA ZIP!"
        return 1
    fi
}

monitor_time_with_logs() {
    local start_time=$(date +%s)
    local last_display_time=$start_time
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local remaining=$((SAFE_TIME - elapsed))
        
        (( remaining <= 0 )) && {
            echo "Timeout approaching! Saving ccache..."
            upload_ccache
            exit 0
        }
        
        if (( current_time - last_display_time >= 300 )); then
            echo -ne "\r$(date): Timer Running. Elapsed: ${elapsed}s / Timeout: ${SAFE_TIME}s | Remaining: ${remaining}s"
            echo -e "\n--- Latest Build Logs ---"
            tail -n 10 "$LOG_FILE"
            echo -e "-------------------------"
            last_display_time=$current_time
        fi
        sleep 1
    done
}

build() {
    echo "Starting build..."
    source build/envsetup.sh || . build/envsetup.sh
    lunch "$MAKEFILENAME-$VARIANT" || exit 1
    [ -n "$EXTRACMD" ] && eval "$EXTRACMD"
    $TARGET -j$(nproc --all) >> "$LOG_FILE" 2>&1 || {
        echo "Build failed!"
        exit 1
    }
}

# ===== Main Execution =====
{
    echo "===== Build Script Starting ====="
    echo "ROM: $MAKEFILENAME"
    echo "Device: $DEVICE_CODENAME"
    echo "Variant: $VARIANT"
    
    # Start monitoring
    : > "$LOG_FILE"
    monitor_time_with_logs &
    TIMER_PID=$!
    
    # Build process
    setup_ccache
    download_ccache || echo "No ccache found, starting fresh"
    build
    
    # Final ccache upload
    compress_and_upload_ccache
    
    # Upload OTA ZIP
    upload_ota
    
    echo "===== Build Completed Successfully ====="
} | tee -a "$LOG_FILE"
