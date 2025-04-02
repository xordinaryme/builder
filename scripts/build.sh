#!/bin/bash

# Variables
SOURCEFORGE_USER="belowzeroiq"
SOURCEFORGE_PROJECT="tnf-images"
SOURCEFORGE_PATH="/home/frs/project/$SOURCEFORGE_PROJECT"
PARTITIONS=("boot" "system" "system_ext" "product" "vendor" "odm")
MAKEFILENAME="lineage_topaz"
VARIANT="userdebug"
ROM_ZIP="lineage_${MAKEFILENAME}_${VARIANT}.zip"

# Function to check and download partition images from SourceForge
download_partition() {
  local partition="$1"
  local filename="${partition}.img"
  echo "Checking for existing $filename on SourceForge..."

  LATEST_IMG=$(wget -qO- "https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/" | \
    grep -oP "${partition}\.img" | sort | tail -n1)

  if [ -n "$LATEST_IMG" ]; then
    echo "$filename found. Downloading..."
    DOWNLOAD_URL="https://downloads.sourceforge.net/project/$SOURCEFORGE_PROJECT/$filename"
    wget -O "$filename" "$DOWNLOAD_URL"
  else
    echo "$filename not found. It will be built."
  fi
}

# Function to upload partition images to SourceForge
upload_partition() {
  local partition="$1"
  local filename="${partition}.img"

  if [ -f "$filename" ]; then
    echo "Uploading $filename to SourceForge..."
    if [ -z "$SOURCEFORGE_PASSWORD" ]; then
      echo "Error: SOURCEFORGE_PASSWORD environment variable is not set."
      exit 1
    fi
    sshpass -p "$SOURCEFORGE_PASSWORD" rsync -avz -e "ssh -o StrictHostKeyChecking=no" "$filename" "$SOURCEFORGE_USER@frs.sourceforge.net:$SOURCEFORGE_PATH/"
    echo "$filename uploaded successfully."
  else
    echo "Skipping upload. $filename not found."
  fi
}

# Function to build a partition
build_partition() {
  local partition="$1"
  echo "Building $partition image..."
  source build/envsetup.sh || . build/envsetup.sh
  lunch $MAKEFILENAME-$VARIANT
  m "$partition"image -j$(nproc --all)
  upload_partition "$partition"  # Upload immediately after building
}

# Main execution
for partition in "${PARTITIONS[@]}"; do
  download_partition "$partition"
  if [ ! -f "${partition}.img" ]; then
    build_partition "$partition"
  fi
done

echo "All partitions processed. Creating full ROM zip..."

# Create full ROM zip from downloaded/generated images
mkdir -p rom_output
for partition in "${PARTITIONS[@]}"; do
  mv "${partition}.img" rom_output/
done

cd rom_output || exit 1
zip -r "../$ROM_ZIP" .
cd ..

# Upload ROM zip
if [ -f "$ROM_ZIP" ]; then
  echo "Uploading full ROM zip to SourceForge..."
  if [ -z "$SOURCEFORGE_PASSWORD" ]; then
    echo "Error: SOURCEFORGE_PASSWORD environment variable is not set."
    exit 1
  fi
  sshpass -p "$SOURCEFORGE_PASSWORD" rsync -avz -e "ssh -o StrictHostKeyChecking=no" "$ROM_ZIP" "$SOURCEFORGE_USER@frs.sourceforge.net:$SOURCEFORGE_PATH/"
  echo "Full ROM zip uploaded successfully."
else
  echo "Full ROM zip creation failed."
fi

echo "ROM build process completed."
