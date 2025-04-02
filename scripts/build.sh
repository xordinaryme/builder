#!/bin/bash

# Variables
CCACHE_DIR=~/.ccache
SOURCEFORGE_USER="belowzeroiq"
SOURCEFORGE_PROJECT="ccache-archive"
SOURCEFORGE_PATH="/home/frs/project/$SOURCEFORGE_PROJECT"
ENCRYPTED_PASSWORD="U2FsdGVkX18sne6G6HgGkna3xag+T3s096aCiBritHQ="
CCACHE_ARCHIVE="ccache-$(date +'%Y%m%d%H%M%S').tar.zst"
SAFE_TIME=5800  # 1 hour and 36 minutes in seconds

MAKEFILENAME="lineage_topaz"
VARIANT="userdebug"
EXTRACMD="make clean"
TARGET="mka bacon"

# Function to set up ccache
setup_ccache() {
  echo "Setting up ccache..."
  export CCACHE_DIR=~/.ccache
  export USE_CCACHE=1
  ccache -M 50G
  ccache -z
  echo "Ccache setup complete."
}

# Function to download ccache from SourceForge
download_ccache() {
  echo "Downloading ccache from SourceForge..."

  # Fetch the latest ccache file name
  LATEST_CCACHE=$(wget -qO- "https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/" | \
    grep -oP 'ccache-[0-9]+\.tar\.gz' | sort | tail -n1)

  if [ -z "$LATEST_CCACHE" ]; then
    echo "No ccache archive found on SourceForge. Starting fresh."
    return
  fi

  # Construct the correct download URL
  DOWNLOAD_URL="https://downloads.sourceforge.net/project/$SOURCEFORGE_PROJECT/$LATEST_CCACHE"

  # Download the ccache archive
  wget -O ccache-latest.tar.zst "$DOWNLOAD_URL"

  if [ ! -f ccache-latest.tar.zst ]; then
    echo "Failed to download ccache from SourceForge. Starting fresh."
    return
  fi

  # Extract the ccache archive using zstd
  mkdir -p ~/.ccache_tmp
  tar -I zstd -xvf ccache-latest.tar.zst -C ~/.ccache_tmp

  # Merge the extracted ccache into the existing ccache directory
  rsync -a --delete ~/.ccache_tmp/ ~/.ccache/

  # Clean up temporary files
  rm -rf ~/.ccache_tmp ccache-latest.tar.zst

  echo "Ccache downloaded and extracted successfully."
}

# Function to upload ccache to SourceForge
upload_ccache() {
  echo "Compressing ccache with store (no compression)..."

  # Create a temporary snapshot of the ccache directory
  SNAPSHOT_DIR=$(mktemp -d)
  rsync -a --delete "$CCACHE_DIR/" "$SNAPSHOT_DIR/"

  # Compress the snapshot with zstd
  tar -I zstd -cf "$CCACHE_ARCHIVE.zst" -C "$SNAPSHOT_DIR" .

  # Clean up the snapshot
  rm -rf "$SNAPSHOT_DIR"

  echo "Uploading ccache to SourceForge..."
  SOURCEFORGE_PASSWORD=$(echo "$ENCRYPTED_PASSWORD" | openssl enc -aes-256-cbc -d -a -pbkdf2 -pass pass:topnotchfreaks)
  sshpass -p "$SOURCEFORGE_PASSWORD" rsync -avz -e "ssh -o StrictHostKeyChecking=no" "$CCACHE_ARCHIVE" "$SOURCEFORGE_USER@frs.sourceforge.net:$SOURCEFORGE_PATH/"

  echo "Ccache uploaded successfully."
}

# Function to monitor time and upload ccache before Cirrus CI timeout
monitor_time_with_logs() {
  local start_time=$(date +%s)
  local log_file="$1"
  local last_display_time=$start_time  # Track the last time logs were displayed
  local display_interval=300          # Set the interval to 5 minutes (300 seconds)

  while true; do
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    local remaining=$((SAFE_TIME - elapsed))
    local since_last_display=$((current_time - last_display_time))

    if (( remaining <= 0 )); then
      echo "Timeout approaching! Saving ccache..."
      upload_ccache
      exit 0
    fi

    # Display logs every 5 minutes
    if (( since_last_display >= display_interval )); then
      echo -ne "\r$(date): Timer Running. Elapsed: ${elapsed}s / Timeout: ${SAFE_TIME}s | Remaining: ${remaining}s"
      echo -e "\n--- Latest Build Logs ---"
      tail -n 10 "$log_file"  # Show the last 10 lines of the build log
      echo -e "-------------------------"
      last_display_time=$current_time  # Update the last display time
    fi

    sleep 1
  done
}

# Function to build the project
build() {
  source build/envsetup.sh || . build/envsetup.sh
  lunch $MAKEFILENAME-$VARIANT
  $EXTRACMD
  # Use one less CPU core for the build
  $TARGET -j$(( $(nproc --all) - 1 )) >> build.log 2>&1  # Redirect build output to a log file
}

# Start background timer with log monitoring
build_log="build.log"
: > "$build_log"  # Clear the log file before starting
monitor_time_with_logs "$build_log" &  
TIMER_PID=$!

# Start build
setup_ccache
download_ccache
build

# Kill the timer if build finishes early
kill $TIMER_PID 2>/dev/null || true

# Final ccache save
upload_ccache
