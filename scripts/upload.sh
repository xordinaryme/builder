#!/bin/bash

# Variables
GITHUB_TOKEN="${GITHUB_TOKEN:?Environment variable GITHUB_TOKEN is required}" # Read from environment
REPO_OWNER="belowzeroiq"     # Replace with your GitHub username or org
REPO_NAME="Builder"          # Replace with your repository name
TAG_NAME="v$(date +'%Y%m%d%H%M%S')"  # Generate a dynamic tag name based on the current timestamp
UPLOAD_URL="https://uploads.github.com/repos/$REPO_OWNER/$REPO_NAME/releases"

# Function to upload files to GitHub release
upload_to_github() {
  # Get the release ID for the specified tag
  RELEASE_ID=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$TAG_NAME" | jq -r '.id')

  if [ "$RELEASE_ID" == "null" ]; then
    echo "Release not found. Please create a release with the tag $TAG_NAME first."
    exit 1
  fi

  # Upload files
  for FILE in ./out/target/product/$DEVICE/*.{zip,img}; do
    if [ -f "$FILE" ]; then
      FILENAME=$(basename "$FILE")
      echo "Uploading $FILENAME to GitHub release..."
      curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: $(file -b --mime-type "$FILE")" \
        --data-binary @"$FILE" \
        "$UPLOAD_URL/$RELEASE_ID/assets?name=$FILENAME"
      echo "Uploaded $FILENAME."
    fi
  done
}

echo "Uploading files to GitHub release with tag $TAG_NAME..."
upload_to_github
