#!/bin/bash
# Create a distributable zip archive of the built app bundle.
set -e

APP_BUNDLE="build/macos/Release/DevCleaner.app"
OUTPUT="DevCleaner.zip"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Build the app first."
    exit 1
fi

rm -f "$OUTPUT"
ditto -c -k --keepParent "$APP_BUNDLE" "$OUTPUT"
echo "Created $OUTPUT"
