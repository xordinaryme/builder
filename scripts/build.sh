#!/bin/bash

# Variables
CCACHE_DIR=~/.ccache
CCACHE_ARCHIVE="ccache-$(date +'%Y%m%d%H%M%S').tar.gz"
SAFE_TIME=5400  # Upload ccache 1 hour 30 min into the build

MAKEFILENAME="lineage_topaz"
VARIANT="userdebug"
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
  LATEST_CCACHE=$(wget -qO- "https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/ccache/" | \
    grep -o 'ccache-.*\.tar\.gz' | sort | tail -n1)

  if [ -z "$LATEST_CCACHE" ]; then
    echo "No ccache archive found on SourceForge. Starting fresh."
    return
  fi

  wget "https://downloads.sourceforge.net/project/$SOURCEFORGE_PROJECT/ccache/$LATEST_CCACHE" -O ccache-latest.tar.gz

  # Extract safely
  mkdir -p ~/.ccache_tmp
  tar -xzf ccache-latest.tar.gz -C ~/.ccache_tmp
  mv ~/.ccache_tmp/* ~/.ccache
  rm -rf ~/.ccache_tmp ccache-latest.tar.gz

  echo "Ccache downloaded and extracted successfully."
}

# Function to upload ccache to PixelDrain
upload_ccache() {
  echo "Compressing ccache..."

  # Create a temporary snapshot of the ccache directory
  SNAPSHOT_DIR=$(mktemp -d)
  rsync -a --delete "$CCACHE_DIR/" "$SNAPSHOT_DIR/"

  # Compress the snapshot
  tar -czf "$CCACHE_ARCHIVE" -C "$SNAPSHOT_DIR" .

  # Clean up the snapshot
  rm -rf "$SNAPSHOT_DIR"

  echo "Uploading ccache to PixelDrain..."

  # Upload the file to PixelDrain using curl
  response=$(curl -s -F "file=@$CCACHE_ARCHIVE" -H "Authorization: Bearer 1f3e28b6-45bd-40e6-8f8a-d36799caccb8" "https://pixeldrain.com/api/file")
  file_id=$(echo "$response" | grep -oP '"id":"\K[^"]+')

  if [ -n "$file_id" ]; then
    echo "Ccache uploaded successfully!"
    echo "Download link: https://pixeldrain.com/u/$file_id"
  else
    echo "Failed to upload ccache to PixelDrain."
    echo "Response: $response"
  fi
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
  $TARGET -j$(nproc --all) >> build.log 2>&1  # Redirect build output to a log file
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
