#!/bin/bash
set -euo pipefail  # Stricter error handling

# ===== Configuration =====
# Load config from external file if exists
CONFIG_FILE="${SCRIPT_DIR:-$(dirname "$0")}/config.env"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Essential Variables with defaults
: "${ROM_NAME:=${MAKEFILENAME%%_*}}"
: "${CCACHE_DIR:=${HOME}/.ccache}"
: "${CCACHE_MAX_SIZE:=50G}"
: "${BUILD_TIMEOUT:=5760}"  # 1h 35m in seconds
: "${UPLOAD_RETRIES:=3}"
: "${LOG_FILE:=build-${ROM_NAME}-$(date +%Y%m%d_%H%M%S).log}"
: "${PIXELDRAIN_API_KEY:?Must set PIXELDRAIN_API_KEY}"

# Derived variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCACHE_TAR="${ROM_NAME}.ccache.tar.gz"
CCACHE_COPY_DIR="${HOME}/ccache_copy"
BUILD_START_TIME=$(date +%s)

# ===== Logging =====
log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }

# ===== Error Handling =====
cleanup() {
    local exit_code=$?
    info "Performing cleanup..."
    kill "$TIMER_PID" 2>/dev/null || true
    rm -rf "$CCACHE_COPY_DIR" "$CCACHE_TAR"
    # Save ccache on non-zero exit if we've been building for a while
    if [ $exit_code -ne 0 ] && [ $(($(date +%s) - BUILD_START_TIME)) -gt 1800 ]; then
        warn "Build failed but running > 30min, saving ccache..."
        compress_and_upload_ccache || true
    fi
    exit $exit_code
}
trap cleanup EXIT

# ===== Build Environment =====
setup_environment() {
    info "Setting up build environment..."
    export USE_CCACHE=1
    export TARGET_ARCH=arm64
    export TARGET_SUPPORTS_32_BIT_APPS=false
    
    # Additional memory optimizations
    export JACK_SERVER_VM_ARGUMENTS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx4g"
    export _JAVA_OPTIONS="-Xmx4g"
}

setup_ccache() {
    info "Setting up ccache..."
    ccache -M "$CCACHE_MAX_SIZE"
    ccache -z
}

# ===== Cloud Storage Functions =====
upload_to_pixeldrain() {
    local file="$1"
    local attempt=1
    
    while [ $attempt -le $UPLOAD_RETRIES ]; do
        info "Upload attempt $attempt/$UPLOAD_RETRIES..."
        response=$(curl -s -X POST \
            -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
            -F "file=@$file" \
            "https://pixeldrain.com/api/file")
            
        file_id=$(echo "$response" | jq -r '.id')
        if [ -n "$file_id" ] && [ "$file_id" != "null" ]; then
            echo "https://pixeldrain.com/u/$file_id"
            return 0
        fi
        
        attempt=$((attempt + 1))
        [ $attempt -le $UPLOAD_RETRIES ] && sleep 5
    done
    return 1
}

download_ccache() {
    info "Checking for existing ccache..."
    local response
    response=$(curl -sf -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/user/files") || return 1

    local ccache_file_id
    ccache_file_id=$(echo "$response" | jq -r --arg CCACHE_TAR "$CCACHE_TAR" \
        '[.files[] | select(.name | test("^" + $CCACHE_TAR + "$"))] | sort_by(.date_upload) | last | .id')
    
    if [ -z "$ccache_file_id" ] || [ "$ccache_file_id" = "null" ]; then
        info "No previous ccache found, starting fresh"
        return 1
    fi

    info "Downloading ccache..."
    if curl -L -o "$CCACHE_TAR" "https://pixeldrain.com/api/file/$ccache_file_id?download"; then
        mkdir -p "$CCACHE_DIR"
        tar -xzf "$CCACHE_TAR" -C "$CCACHE_DIR"
        rm -f "$CCACHE_TAR"
        return 0
    fi
    rm -f "$CCACHE_TAR"
    return 1
}

compress_and_upload_ccache() {
    info "Creating safe copy of ccache for ${ROM_NAME}..."
    mkdir -p "$CCACHE_COPY_DIR"
    rsync -a --delete "$CCACHE_DIR/" "$CCACHE_COPY_DIR/" || cp -a "$CCACHE_DIR/." "$CCACHE_COPY_DIR/"

    info "Compressing ccache..."
    tar -czf "$CCACHE_TAR" -C "$CCACHE_COPY_DIR" . || return 1

    info "Uploading ${CCACHE_TAR} to PixelDrain..."
    response=$(curl -s -X POST \
        -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$CCACHE_TAR" \
        "https://pixeldrain.com/api/file") || return 1

    file_id=$(echo "$response" | jq -r '.id')
    if [ -n "$file_id" ] && [ "$file_id" != "null" ]; then
        echo "Uploaded: https://pixeldrain.com/u/$file_id"
    else
        echo "Failed to upload ccache!"
        return 1
    fi
}

upload_ota() {
    info "Uploading OTA ZIP..."
    ota_file=$(find "out/target/product/${DEVICE_CODENAME}" -name "Project_Infinity-X*.zip" -type f | head -n 1)
    
    if [ -z "$ota_file" ]; then
        error "No OTA ZIP file found!"
        return 1
    fi
    
    info "Found OTA ZIP: $ota_file"
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
            info "Timeout approaching! Saving ccache..."
            compress_and_upload_ccache
            exit 0
        }
        
        if (( current_time - last_display_time >= 300 )); then
            info "Timer Running. Elapsed: ${elapsed}s / Timeout: ${SAFE_TIME}s | Remaining: ${remaining}s"
            info "Recent build log:"
            tail -n 10 "$LOG_FILE" || true
            last_display_time=$current_time
        fi
        sleep 1
   done
}

build() {
    info "Starting build..."
    source build/envsetup.sh 2>/dev/null || . build/envsetup.sh
    
    if ! lunch "$MAKEFILENAME-$VARIANT"; then
        error "Failed to configure lunch target"
        return 1
    fi
    
    [ -n "${EXTRACMD:-}" ] && eval "$EXTRACMD"
    
    if ! $TARGET -j$(nproc --all) >> "$LOG_FILE" 2>&1; then
        error "Build failed! Check $LOG_FILE for details"
        return 1
    fi
    
    info "Build completed successfully"
}

# ===== Main Execution =====
#{
    info "===== Build Script Starting ====="
    info "ROM: $MAKEFILENAME"
    info "Device: $DEVICE_CODENAME"
    info "Variant: $VARIANT"
    
    setup_environment
    setup_ccache
    download_ccache || info "Starting with fresh ccache"
    
    # Start build monitor
    monitor_build &
    TIMER_PID=$!
    
    if execute_build; then
        info "Uploading build artifacts..."
        if ! upload_ota; then
            error "Failed to upload OTA"
            exit 1
        fi
        
        info "Saving ccache..."
        if ! compress_and_upload_ccache; then
            error "Failed to save ccache"
            exit 1
        fi
        
        info "Build completed successfully!"
    else
        error "Build failed!"
        exit 1
    fi
#} | tee -a "$LOG_FILE"
