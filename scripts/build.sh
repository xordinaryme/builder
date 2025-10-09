#!/bin/bash
set -e
ROM_NAME="${MAKEFILENAME%%_*}"
CCACHE_DIR="$HOME/.ccache"
CCACHE_TAR="${ROM_NAME}.ccache.tar.gz"
CCACHE_COPY_DIR="$HOME/ccache_copy"
SAFE_TIME=3600
LOG_FILE="build.log"
OTA_ZIP="${OUT_DIR}/target/product/${DEVICE_CODENAME}/*.zip"
export LC_ALL=C

cleanup() {
    kill "$TIMER_PID" 2>/dev/null || true
    rm -rf "$CCACHE_COPY_DIR" "$CCACHE_TAR"
}
trap cleanup EXIT

setup_ccache() {
    export USE_CCACHE=1
    ccache -M 50G
    ccache -z
}

download_ccache() {
    echo "Checking for existing ccache..."
    echo "Looking for file: $CCACHE_TAR"
    
    # Check if API key is set
    if [ -z "$PIXELDRAIN_API_KEY" ]; then
        echo "Error: PIXELDRAIN_API_KEY not set"
        return 1
    fi
    
    # Fetch file list using the correct endpoint
    echo "Fetching file list from Pixeldrain..."
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/user/files")
    
    # Extract HTTP status code
    http_code=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    # Extract response body (remove status line)
    response_body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo "HTTP Status: $http_code"
    
    if [ "$http_code" != "200" ]; then
        echo "Error: API returned status $http_code"
        echo "Response: $response_body"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$response_body" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response from API"
        echo "Response: $response_body"
        return 1
    fi
    
    # Check if .files exists
    files_count=$(echo "$response_body" | jq '.files | length' 2>/dev/null)
    if [ "$files_count" = "null" ] || [ -z "$files_count" ]; then
        echo "Error: Response does not contain .files array"
        echo "Response structure: $(echo "$response_body" | jq 'keys')"
        return 1
    fi
    
    echo "Found $files_count files in account"
    
    # List all files for debugging
    echo "Available files:"
    echo "$response_body" | jq -r '.files[]? | .name' 2>/dev/null || echo "  (none)"
    
    # Extract file ID - exact match on filename
    ccache_file_id=$(echo "$response_body" | jq -r --arg CCACHE_TAR "$CCACHE_TAR" \
        '(.files // []) | map(select(.name == $CCACHE_TAR)) | sort_by(.date_upload) | last | .id // empty' 2>/dev/null)
    
    if [ -z "$ccache_file_id" ]; then
        echo "No existing ccache found for: $CCACHE_TAR"
        return 1
    fi
    
    echo "Found ccache file ID: $ccache_file_id"
    echo "Downloading ccache with aria2..."
    
    # Use aria2c for faster download with multiple connections
    if ! aria2c \
        --max-connection-per-server=16 \
        --split=16 \
        --min-split-size=1M \
        --file-allocation=none \
        --continue=true \
        --check-certificate=false \
        --out="$CCACHE_TAR" \
        --header="Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/file/$ccache_file_id?download"; then
        
        echo "Error: Failed to download ccache with aria2"
        # Fallback to curl if aria2 fails
        echo "Trying fallback with curl..."
        if ! curl -L -o "$CCACHE_TAR" \
            -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
            "https://pixeldrain.com/api/file/$ccache_file_id?download"; then
            echo "Error: Fallback download also failed"
            rm -f "$CCACHE_TAR"
            return 1
        fi
    fi
    
    echo "Extracting ccache..."
    mkdir -p "$CCACHE_DIR"
    
    if ! tar -xzf "$CCACHE_TAR" -C "$CCACHE_DIR"; then
        echo "Error: Failed to extract ccache"
        rm -f "$CCACHE_TAR"
        return 1
    fi
    
    rm -f "$CCACHE_TAR"
    echo "Ccache downloaded and extracted successfully"
    return 0
}

compress_and_upload_ccache() {
    echo "Compressing ccache..."
    mkdir -p "$CCACHE_COPY_DIR"
    
    if ! rsync -a --delete "$CCACHE_DIR/" "$CCACHE_COPY_DIR/" 2>/dev/null; then
        echo "rsync not available, using cp..."
        cp -a "$CCACHE_DIR/." "$CCACHE_COPY_DIR/" || return 1
    fi
    
    if ! tar -czf "$CCACHE_TAR" -C "$CCACHE_COPY_DIR" .; then
        echo "Error: Failed to compress ccache"
        return 1
    fi
    
    echo "Uploading ccache..."
    response=$(curl -s -X POST -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$CCACHE_TAR" "https://pixeldrain.com/api/file")
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to upload ccache"
        return 1
    fi
    
    file_id=$(echo "$response" | jq -r '.id // empty')
    
    if [ -n "$file_id" ]; then
        echo "Ccache uploaded: https://pixeldrain.com/u/$file_id"
        return 0
    else
        echo "Error: Upload succeeded but no file ID returned"
        return 1
    fi
}

upload_ota() {
    echo "Looking for OTA file..."
    ota_file=$(find "out/target/product/${DEVICE_CODENAME}" -name "PixelOS*.zip" -type f 2>/dev/null | head -n 1)
    
    if [ -z "$ota_file" ]; then
        echo "Warning: No OTA file found"
        return 1
    fi
    
    echo "Found OTA: $ota_file"
    echo "Uploading OTA..."
    
    response=$(curl -s -X POST -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$ota_file" "https://pixeldrain.com/api/file")
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to upload OTA"
        return 1
    fi
    
    file_id=$(echo "$response" | jq -r '.id // empty')
    
    if [ -n "$file_id" ]; then
        echo "OTA ZIP uploaded: https://pixeldrain.com/u/$file_id"
        return 0
    else
        echo "Error: Upload succeeded but no file ID returned"
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
        
        if (( remaining <= 0 )); then
            echo -e "\n\nTime limit reached! Saving ccache..."
            compress_and_upload_ccache
            exit 0
        fi
        
        if (( current_time - last_display_time >= 300 )); then
            echo -e "\n$(date): Elapsed: ${elapsed}s | Remaining: ${remaining}s"
            if [ -f "$LOG_FILE" ]; then
                echo "--- Last 10 lines of build log ---"
                tail -n 10 "$LOG_FILE"
                echo "-----------------------------------"
            fi
            last_display_time=$current_time
        fi
        
        sleep 1
    done
}

build() {
    echo "Setting up build environment..."
    . build/envsetup.sh
    
    echo "Running lunch for $MAKEFILENAME-$VARIANT..."
    if ! lunch "$MAKEFILENAME-bp1a-$VARIANT"; then
        echo "Error: lunch failed"
        exit 1
    fi
    
    echo "Starting build with target: $TARGET"
    $TARGET -j$(nproc)
}

# Main execution
echo "========================================="
echo "ROM: $MAKEFILENAME"
echo "Device: $DEVICE_CODENAME"
echo "Variant: $VARIANT"
echo "Target: $TARGET"
echo "Safe time: $SAFE_TIME seconds ($(($SAFE_TIME / 60)) minutes)"
echo "========================================="

# Initialize log file
: > "$LOG_FILE"

# Start time monitor in background
monitor_time_with_logs &
TIMER_PID=$!

# Setup ccache
setup_ccache

# Try to download existing ccache
if download_ccache; then
    echo "Using existing ccache"
else
    echo "Starting fresh build without ccache"
fi

# Build the ROM
build 2>&1 | tee -a "$LOG_FILE"

# Upload OTA if successful
upload_ota || echo "Warning: OTA upload failed or not found"

# Save ccache for next build
compress_and_upload_ccache || echo "Warning: Ccache upload failed"

echo "Build complete!"
