#!/bin/bash

# ============================================================================
# BUILD SCRIPT
# ============================================================================
# Builds the DevCleaner app bundle with nimpacker and signs it.
#
# By default the app is ad-hoc signed (no Developer ID required). This allows
# full file system access for the cleaning tool.
#
# For distribution, set SIGN_IDENTITY to your Developer ID Application identity:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh
#
# Set NIMPACKER to point to your local nimpacker binary if it is not on PATH.
# ============================================================================

set -e

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NIMPACKER="${NIMPACKER:-nimpacker}"

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "=== DevCleaner Build (ad-hoc signing) ==="
    echo "For distribution, set SIGN_IDENTITY to your Developer ID Application identity."
else
    echo "=== DevCleaner Build (Developer ID signing) ==="
    echo "Signing identity: $SIGN_IDENTITY"
fi
echo ""

# Build the app bundle with nimpacker.
echo "[1/2] Building app bundle with nimpacker..."
"$NIMPACKER" build -t=macos -r

# Sign the resulting app bundle.
echo "[2/2] Signing app bundle..."
codesign --force --options runtime --deep --sign "$SIGN_IDENTITY" \
    --entitlements "app.entitlements" \
    "build/macos/Release/DevCleaner.app"

echo ""
echo "Build complete: build/macos/Release/DevCleaner.app"

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo ""
    echo "Note: This build uses ad-hoc signing."
    echo "Users will see 'downloaded from internet' warning on first launch."
    echo "To bypass: Right-click app > Open, then click Open in dialog."
fi
