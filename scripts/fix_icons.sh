#!/bin/bash

ASSETS_DIR="GitMenuBar/Assets.xcassets/AppIcon.appiconset"

# Function to resize image
resize_icon() {
    local filename="$1"
    local size="$2"
    echo "Resizing $filename to ${size}x${size}..."
    sips -z "$size" "$size" "$ASSETS_DIR/$filename" 2>&1 > /dev/null
}

echo "Fixing AppIcon assets..."

# Resize icons based on the error log and Contents.json
resize_icon "icon 4.png" 16
resize_icon "icon 5.png" 32
resize_icon "icon 6.png" 32
resize_icon "icon 3.png" 64
resize_icon "icon 2.png" 128
resize_icon "icon 1.png" 256
resize_icon "icon 7.png" 256
resize_icon "icon 9.png" 1024

echo "AppIcon assets fixed."
