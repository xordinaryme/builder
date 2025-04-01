#!/bin/bash

# Variables
SOURCEFORGE_USER="belowzeroiq"  # Replace with your SourceForge username
SOURCEFORGE_PROJECT="Builder"  # Replace with your SourceForge project name
SOURCEFORGE_PATH="/home/frs/project/$SOURCEFORGE_PROJECT/roms"  # Destination path on SourceForge

# Function to upload ROMs to SourceForge
upload_to_sourceforge() {
  echo "Uploading ROMs to SourceForge..."

  # Loop through all ROM files in the output directory
  for FILE in ./out/target/product/$DEVICE/*.{zip,img}; do
    if [ -f "$FILE" ]; then
      FILENAME=$(basename "$FILE")
      echo "Uploading $FILENAME to SourceForge..."
      sshpass -p "$SOURCEFORGE_PASSWORD" rsync -avz -e "ssh -o StrictHostKeyChecking=no" "$FILE" "$SOURCEFORGE_USER@frs.sourceforge.net:$SOURCEFORGE_PATH/"
      echo "Uploaded $FILENAME to SourceForge."
    fi
  done
}

echo "Uploading files to SourceForge..."
upload_to_sourceforge
