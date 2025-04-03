#!/bin/bash

# Variables
PARTITIONS=("boot" "system" "system_ext" "product" "vendor" "odm")
ROM_NAME="$MAKEFILENAME"
TARGET_FILES="out/target/product/$DEVICE_CODENAME/ota_target_files.zip"
OTA_ZIP="out/target/product/$DEVICE_CODENAME/lineage_${MAKEFILENAME}_${VARIANT}.zip"
LOG_FILE="build.log"

# CCache settings
CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
CCACHE_COPY_DIR="$HOME/ccache_copy"
CCACHE_TAR="ccache.tar.gz"
CCACHE_UPLOAD_INTERVAL=$((30 * 60))  # 30 minutes

# Timeout settings
TIMEOUT_SECONDS=5700  # 1 hour 35 minutes
START_TIME=$(date +%s)
LAST_CCACHE_CHECK=$START_TIME
LAST_LOG_TIME=$START_TIME
LOG_INTERVAL=$((5 * 60))  # 5 minutes
TIMEOUT_REACHED=0

# Function to show status information
show_status() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local remaining=$((TIMEOUT_SECONDS - elapsed))
    
    echo ""
    echo "===== STATUS UPDATE [$(date '+%Y-%m-%d %H:%M:%S')] ====="
    echo "Elapsed time: $(printf '%02d:%02d:%02d' $((elapsed/3600)) $(( (elapsed%3600)/60 )) $((elapsed%60)))"
    echo "Remaining time: $(printf '%02d:%02d:%02d' $((remaining/3600)) $(( (remaining%3600)/60 )) $((remaining%60)))"
    echo "Timeout: $(printf '%02d:%02d:%02d' $((TIMEOUT_SECONDS/3600)) $(( (TIMEOUT_SECONDS%3600)/60 )) $((TIMEOUT_SECONDS%60)))"
    
    echo ""
    echo "--- Last 10 lines of build log ---"
    tail -n 10 "$LOG_FILE" 2>/dev/null || echo "No build log available yet"
    
    echo ""
    echo "--- CCache Statistics ---"
    ccache -s
    
    echo "===== END OF STATUS ====="
    echo ""
}

# Function to check remaining time and upload ccache if needed
check_timeout() {
    local current_time=$(date +%s)
    
    # Show status every LOG_INTERVAL seconds
    if [ $((current_time - LAST_LOG_TIME)) -ge $LOG_INTERVAL ]; then
        show_status
        LAST_LOG_TIME=$current_time
    fi
    
    local elapsed=$((current_time - START_TIME))
    local remaining=$((TIMEOUT_SECONDS - elapsed))
    
    if [ $remaining -le 0 ]; then
        echo "Timeout reached (1h 40m). Preparing to upload ccache..."
        TIMEOUT_REACHED=1
        compress_and_upload_ccache
        show_status
        exit 0
    fi
    
    # Check if we should upload ccache periodically
    local time_since_last_check=$((current_time - LAST_CCACHE_CHECK))
    if [ $time_since_last_check -ge $CCACHE_UPLOAD_INTERVAL ]; then
        echo "Periodic ccache check (every ${CCACHE_UPLOAD_INTERVAL}s)..."
        if [ $remaining -le $((TIMEOUT_SECONDS / 4)) ]; then
            echo "Approaching timeout - preparing to upload ccache..."
            compress_and_upload_ccache
            LAST_CCACHE_CHECK=$current_time
        fi
    fi
    
    return 0
}

# Function to run commands with timeout checking and logging
run_with_timeout() {
    local cmd="$@"
    
    while true; do
        check_timeout
        
        if [ $TIMEOUT_REACHED -eq 1 ]; then
            return 1
        fi
        
        # Run the command with logging
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing: $cmd" >> "$LOG_FILE"
        $cmd >> "$LOG_FILE" 2>&1 &
        local cmd_pid=$!
        
        # Monitor the command with timeout checks
        while ps -p $cmd_pid > /dev/null; do
            check_timeout
            if [ $TIMEOUT_REACHED -eq 1 ]; then
                kill $cmd_pid 2>/dev/null
                wait $cmd_pid 2>/dev/null
                return 1
            fi
            sleep 10
        done
        
        wait $cmd_pid
        local exit_status=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Command exited with status: $exit_status" >> "$LOG_FILE"
        return $exit_status
    done
}

# Function to check for and download ccache from PixelDrain
download_ccache() {
    echo "Checking for existing ccache on PixelDrain..."
    
    # Make API request to list files
    response=$(curl -s -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/user/files")
    
    # Find the newest ccache file
    ccache_file_id=$(echo "$response" | jq -r '[.files[] | select(.name | contains("ccache"))] | sort_by(.date_upload) | last | .id')
    
    if [ -n "$ccache_file_id" ] && [ "$ccache_file_id" != "null" ]; then
        echo "Found ccache archive on PixelDrain (ID: $ccache_file_id), downloading..."
        
        # Download the ccache archive
        if curl -L -o "$CCACHE_TAR" "https://pixeldrain.com/api/file/$ccache_file_id?download"; then
            echo "Extracting ccache..."
            mkdir -p "$CCACHE_DIR"
            tar -xzf "$CCACHE_TAR" -C "$CCACHE_DIR"
            echo "CCache restored successfully."
            rm -f "$CCACHE_TAR"
            return 0
        else
            echo "Failed to download ccache archive."
            rm -f "$CCACHE_TAR"
            return 1
        fi
    else
        echo "No ccache archive found on PixelDrain."
        return 1
    fi
}

# Function to safely compress and upload ccache
compress_and_upload_ccache() {
    echo "Creating safe copy of ccache for compression..."
    
    mkdir -p "$CCACHE_COPY_DIR"
    
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$CCACHE_DIR/" "$CCACHE_COPY_DIR/"
    else
        echo "Warning: rsync not found, using cp which may be slower"
        cp -a "$CCACHE_DIR/." "$CCACHE_COPY_DIR/"
    fi
    
    echo "Compressing ccache copy..."
    if tar -czf "$CCACHE_TAR" -C "$CCACHE_COPY_DIR" .; then
        echo "Uploading ccache to PixelDrain..."
        response=$(curl -s -X POST \
            -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
            -F "file=@$CCACHE_TAR" \
            "https://pixeldrain.com/api/file")
        
        file_id=$(echo "$response" | jq -r '.id')
        if [ -n "$file_id" ] && [ "$file_id" != "null" ]; then
            echo "ccache uploaded successfully to PixelDrain."
            echo "File ID: $file_id"
            echo "Download URL: https://pixeldrain.com/u/$file_id"
        else
            echo "Failed to upload ccache to PixelDrain."
            echo "Response: $response"
        fi
    else
        echo "Failed to compress ccache directory."
    fi
    
    rm -rf "$CCACHE_COPY_DIR" "$CCACHE_TAR"
}

# Function to get .img file IDs from PixelDrain API
get_pixeldrain_file_ids() {
    echo "Fetching available .img files from PixelDrain..."
    
    response=$(curl -s -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/user/files")
    
    if [ -z "$response" ]; then
        echo "Failed to fetch files from PixelDrain"
        return 1
    fi
    
    declare -gA PIXELDRAIN_FILE_IDS
    while IFS= read -r line; do
        file_id=$(echo "$line" | jq -r '.id')
        file_name=$(echo "$line" | jq -r '.name')
        if [[ "$file_name" == *.img ]]; then
            PIXELDRAIN_FILE_IDS["$file_name"]="$file_id"
            echo "Found image file: $file_name (ID: $file_id)"
        fi
    done < <(echo "$response" | jq -c '.files[]')
    
    echo "Found ${#PIXELDRAIN_FILE_IDS[@]} .img files on PixelDrain"
}

# Function to check and download partition images from PixelDrain
download_partition() {
    check_timeout
    
    local partition="$1"
    local filename="${partition}.img"
    local image_dir="out/target/product/$DEVICE_CODENAME"
    local rom_filename="${ROM_NAME}_${filename}"

    mkdir -p "$image_dir"

    echo "Checking for existing $filename..."

    if [ -z "${PIXELDRAIN_FILE_IDS[$filename]}" ]; then
        echo "$filename not found on PixelDrain. It will be built."
        return
    fi

    local file_id="${PIXELDRAIN_FILE_IDS[$filename]}"
    echo "Attempting to download $filename (ID: $file_id) from PixelDrain..."
    
    if curl -L -o "$image_dir/$rom_filename" "https://pixeldrain.com/api/file/$file_id?download"; then
        echo "$filename downloaded successfully from PixelDrain."
        mv "$image_dir/$rom_filename" "$image_dir/$filename"
    else
        echo "Failed to download $filename from PixelDrain. It will be built."
        rm -f "$image_dir/$rom_filename"
    fi
}

# Function to upload .img files to PixelDrain
upload_file() {
    check_timeout
    
    local file_path="$1"
    local file_name=$(basename "$file_path")

    if [[ "$file_name" != *.img ]]; then
        echo "Skipping upload of non-image file: $file_name"
        return
    fi

    if [ ! -f "$file_path" ]; then
        echo "Skipping upload. $file_name not found."
        return
    fi

    echo "Uploading $file_name to PixelDrain..."
    
    response=$(curl -s -X POST \
        -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$file_path" \
        "https://pixeldrain.com/api/file")
    
    file_id=$(echo "$response" | jq -r '.id')
    
    if [ -n "$file_id" ] && [ "$file_id" != "null" ]; then
        echo "$file_name uploaded successfully to PixelDrain."
        echo "File ID: $file_id"
        echo "Download URL: https://pixeldrain.com/u/$file_id"
        PIXELDRAIN_FILE_IDS["$file_name"]="$file_id"
    else
        echo "Failed to upload $file_name to PixelDrain."
        echo "Response: $response"
    fi
}

# Function to build a partition image if not found
build_partition() {
    check_timeout
    
    local partition="$1"
    echo "Building $partition image..."
    source build/envsetup.sh || . build/envsetup.sh
    lunch $MAKEFILENAME-$VARIANT
    m "$partition"image -j$(( $(nproc --all) - 1 ))
    upload_file "out/target/product/$DEVICE_CODENAME/${partition}.img"
}

# Function to generate `payload.bin` and OTA ZIP
generate_ota_zip() {
    check_timeout
    
    echo "Generating OTA ZIP with payload.bin..."

    source build/envsetup.sh
    lunch $MAKEFILENAME-$VARIANT
    m dist

    if [ ! -f "$TARGET_FILES" ]; then
        echo "Error: Target files package ($TARGET_FILES) not found."
        exit 1
    fi

    ./build/tools/releasetools/ota_from_target_files -v \
        -p out/host/linux-x86 \
        --block \
        --full \
        "$TARGET_FILES" "$OTA_ZIP"

    upload_file "$OTA_ZIP"
}

# Setup ccache with download option
setup_ccache() {
    echo "Setting up ccache..."
    export USE_CCACHE=1
    export CCACHE_EXEC=$(which ccache)
    export CCACHE_COMPRESS=1
    export CCACHE_COMPRESSLEVEL=6
    export CCACHE_DIR
    
    # Try to download existing ccache first
    if download_ccache; then
        echo "Using restored ccache."
    else
        echo "Starting with fresh ccache."
        ccache -M 50G
        ccache -z
    fi
}

# Main execution
{
    echo "===== BUILD STARTED [$(date '+%Y-%m-%d %H:%M:%S')] ====="
    echo "Timeout set to: $(printf '%02d:%02d:%02d' $((TIMEOUT_SECONDS/3600)) $(( (TIMEOUT_SECONDS%3600)/60 )) $((TIMEOUT_SECONDS%60)))"
    
    setup_ccache
    get_pixeldrain_file_ids

    for partition in "${PARTITIONS[@]}"; do
        run_with_timeout download_partition "$partition"
        if [ ! -f "out/target/product/$DEVICE_CODENAME/${partition}.img" ]; then
            run_with_timeout build_partition "$partition"
        fi
    done

    if [ $TIMEOUT_REACHED -eq 0 ]; then
        echo "All partitions processed. Generating OTA ZIP..."
        run_with_timeout generate_ota_zip
        echo "ROM build process completed."
        ccache -s
    fi
    
    echo "===== BUILD FINISHED [$(date '+%Y-%m-%d %H:%M:%S')] ====="
} | tee -a "$LOG_FILE"

# Final status report
show_status
