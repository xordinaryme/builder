#!/bin/bash

# Function to set up ccache
setup_ccache() {
  echo "Setting up ccache..."
  export CCACHE_DIR=~/.ccache
  export USE_CCACHE=1
  ccache -M 50G # Set maximum cache size to 50GB
  ccache -z     # Zero statistics
  echo "Ccache setup complete."
}

# Function to download ccache from GitHub
download_ccache() {
  echo "Downloading ccache from GitHub repository..."
  CCACHE_ARCHIVE="ccache-latest.tar.gz"

  # Download the latest ccache archive from the GitHub release
  curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -L "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" | \
    jq -r '.assets[] | select(.name | startswith("ccache-")) | .browser_download_url' | \
    xargs curl -s -L -o "$CCACHE_ARCHIVE"

  if [ -f "$CCACHE_ARCHIVE" ]; then
    echo "Extracting ccache archive..."
    tar -xzf "$CCACHE_ARCHIVE" -C ~/
    echo "Ccache downloaded and extracted successfully."
  else
    echo "No ccache archive found. Starting with an empty ccache."
  fi
}

# Function to upload ccache to GitHub
upload_ccache() {
  echo "Uploading ccache to GitHub repository..."
  CCACHE_ARCHIVE="ccache-$(date +'%Y%m%d%H%M%S').tar.gz"
  tar -czf "$CCACHE_ARCHIVE" ~/.ccache

  # Upload to GitHub using the API
  curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/gzip" \
    --data-binary @"$CCACHE_ARCHIVE" \
    "https://uploads.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/assets?name=$CCACHE_ARCHIVE"

  echo "Ccache uploaded successfully as $CCACHE_ARCHIVE."
}

# Function to build the project
build() {
  source build/envsetup.sh || . build/envsetup.sh
  lunch $MAKEFILENAME-$VARIENT
  #export SKIP_ABI_CHECKS=true
  #export SKIP_API_CHECKS=true
  #export ALLOW_MISSING_DEPENDENCIES=true
  #export PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS=false
  $EXTRACMD
  $TARGET -j$(nproc --all) & sleep 95m
}

# Trap to ensure ccache is uploaded on exit
trap upload_ccache EXIT

echo "Initializing Build System"
setup_ccache
download_ccache
build
