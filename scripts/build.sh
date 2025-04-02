#!/bin/bash

# Variables
PARTITIONS=("boot" "system" "system_ext" "product" "vendor" "odm")
ROM_NAME="$MAKEFILENAME"  # Define the ROM name here (this will be used as a prefix)
TARGET_FILES="out/target/product/$DEVICE_CODENAME/ota_target_files.zip"
OTA_ZIP="out/target/product/$DEVICE_CODENAME/lineage_${MAKEFILENAME}_${VARIANT}.zip"

# Function to get .img file IDs from PixelDrain API
get_pixeldrain_file_ids() {
    echo "Fetching available .img files from PixelDrain..."
    
    # Make API request to list files
    response=$(curl -s -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        "https://pixeldrain.com/api/user/files")
    
    # Check if response is valid
    if [ -z "$response" ]; then
        echo "Failed to fetch files from PixelDrain"
        return 1
    fi
    
    # Parse response and create associative array of .img filename -> file_id
    declare -gA PIXELDRAIN_FILE_IDS
    while IFS= read -r line; do
        file_id=$(echo "$line" | jq -r '.id')
        file_name=$(echo "$line" | jq -r '.name')
        # Only include .img files
        if [[ "$file_name" == *.img ]]; then
            PIXELDRAIN_FILE_IDS["$file_name"]="$file_id"
            echo "Found image file: $file_name (ID: $file_id)"
        fi
    done < <(echo "$response" | jq -c '.files[]')
    
    echo "Found ${#PIXELDRAIN_FILE_IDS[@]} .img files on PixelDrain"
}

# Function to check and download partition images from PixelDrain
download_partition() {
    local partition="$1"
    local filename="${partition}.img"
    local image_dir="out/target/product/$DEVICE_CODENAME"
    local rom_filename="${ROM_NAME}_${filename}"  # Add ROM name as prefix to the filename

    # Ensure the target directory exists
    mkdir -p "$image_dir"

    echo "Checking for existing $filename..."

    # Check if file exists in PixelDrain
    if [ -z "${PIXELDRAIN_FILE_IDS[$filename]}" ]; then
        echo "$filename not found on PixelDrain. It will be built."
        return
    fi

    local file_id="${PIXELDRAIN_FILE_IDS[$filename]}"
    echo "Attempting to download $filename (ID: $file_id) from PixelDrain..."
    
    # Try to download the file
    if curl -L -o "$image_dir/$rom_filename" "https://pixeldrain.com/api/file/$file_id?download"; then
        echo "$filename downloaded successfully from PixelDrain."
        # Rename the downloaded image to its default name (without ROM prefix)
        echo "Renaming $rom_filename to $filename..."
        mv "$image_dir/$rom_filename" "$image_dir/$filename"
    else
        echo "Failed to download $filename from PixelDrain. It will be built."
        rm -f "$image_dir/$rom_filename"  # Clean up any partial download
    fi
}

# Function to upload .img files to PixelDrain
upload_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")

    # Only upload .img files
    if [[ "$file_name" != *.img ]]; then
        echo "Skipping upload of non-image file: $file_name"
        return
    fi

    if [ ! -f "$file_path" ]; then
        echo "Skipping upload. $file_name not found."
        return
    fi

    echo "Uploading $file_name to PixelDrain..."
    
    # Upload the file to PixelDrain
    response=$(curl -s -X POST \
        -H "Authorization: Basic $(echo -n ":$PIXELDRAIN_API_KEY" | base64)" \
        -F "file=@$file_path" \
        "https://pixeldrain.com/api/file")
    
    # Extract file ID from response
    file_id=$(echo "$response" | jq -r '.id')
    
    if [ -n "$file_id" ] && [ "$file_id" != "null" ]; then
        echo "$file_name uploaded successfully to PixelDrain."
        echo "File ID: $file_id"
        echo "Download URL: https://pixeldrain.com/u/$file_id"
        
        # Update our file IDs cache
        PIXELDRAIN_FILE_IDS["$file_name"]="$file_id"
    else
        echo "Failed to upload $file_name to PixelDrain."
        echo "Response: $response"
    fi
}

# Function to build a partition image if not found
build_partition() {
    local partition="$1"
    echo "Building $partition image..."
    source build/envsetup.sh || . build/envsetup.sh
    lunch $MAKEFILENAME-$VARIANT
    m "$partition"image -j$(( $(nproc --all) - 1 ))
    upload_file "out/target/product/$DEVICE_CODENAME/${partition}.img"  # Upload immediately after building
}

# Function to generate `payload.bin` and OTA ZIP
generate_ota_zip() {
    echo "Generating OTA ZIP with payload.bin..."

    # Build the target-files package first
    source build/envsetup.sh
    lunch $MAKEFILENAME-$VARIANT
    m dist

    # Check if the target-files package was generated
    if [ ! -f "$TARGET_FILES" ]; then
        echo "Error: Target files package ($TARGET_FILES) not found."
        exit 1
    fi

    # Use `ota_from_target_files` to create the OTA ZIP (with payload.bin)
    ./build/tools/releasetools/ota_from_target_files -v \
        -p out/host/linux-x86 \
        --block \
        --full \
        "$TARGET_FILES" "$OTA_ZIP"

    # Upload the OTA ZIP after generation
    upload_file "$OTA_ZIP"
}

# Main execution

# First get all available .img files from PixelDrain
get_pixeldrain_file_ids

# Process each partition
for partition in "${PARTITIONS[@]}"; do
    download_partition "$partition"
    if [ ! -f "out/target/product/$DEVICE_CODENAME/${partition}.img" ]; then
        build_partition "$partition"
    fi
done

echo "All partitions processed. Generating OTA ZIP..."
generate_ota_zip

echo "ROM build process completed."
