#!/bin/bash

# Variables
CCACHE_DIR=~/.ccache
SOURCEFORGE_USER="belowzeroiq"
SOURCEFORGE_PROJECT="ccache-archive"
SOURCEFORGE_PATH="/home/frs/project/$SOURCEFORGE_PROJECT/ccache"
CCACHE_ARCHIVE="ccache-$(date +'%Y%m%d%H%M%S').tar.gz"
SAFE_TIME=6000  # Upload ccache 1 hour 40 min into the build

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

# Function to upload ccache to SourceForge
upload_ccache() {
  echo "Compressing ccache..."
  tar -czf "$CCACHE_ARCHIVE" -C "$CCACHE_DIR" .

  echo "Uploading ccache to SourceForge..."
  rsync -avz -e ssh "$CCACHE_ARCHIVE" "$SOURCEFORGE_USER@frs.sourceforge.net:$SOURCEFORGE_PATH/"

  echo "Ccache uploaded successfully."
}

# Function to monitor time and upload ccache before Cirrus CI timeout
monitor_time_with_logs() {
  local start_time=$(date +%s)
  local log_file="$1"

  while true; do
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    local remaining=$((SAFE_TIME - elapsed))

    if (( remaining <= 0 )); then
      echo "Timeout approaching! Saving ccache..."
      upload_ccache
      exit 0
    fi

    # Display countdown timer and latest build logs
    echo -ne "\r$(date): Timer Running. Elapsed: ${elapsed}s / Timeout: ${SAFE_TIME}s | Remaining: ${remaining}s"
    echo -e "\n--- Latest Build Logs ---"
    tail -n 10 "$log_file"  # Show the last 10 lines of the build log
    echo -e "-------------------------"

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
