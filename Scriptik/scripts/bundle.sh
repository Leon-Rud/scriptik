#!/bin/bash
# Build Scriptik.app from SPM executable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Scriptik"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BINARY_NAME="Scriptik"

echo "Building $APP_NAME..."

# Use Homebrew Swift if available, otherwise default
if [ -x /opt/homebrew/opt/swift/bin/swift ]; then
    SWIFT=/opt/homebrew/opt/swift/bin/swift
else
    SWIFT=swift
fi

# Build release binary
cd "$PROJECT_DIR"
"$SWIFT" build -c release --disable-sandbox 2>&1

BUILT_BINARY="$("$SWIFT" build -c release --disable-sandbox --show-bin-path)/$BINARY_NAME"

if [ ! -f "$BUILT_BINARY" ]; then
    echo "ERROR: Build failed - binary not found"
    exit 1
fi

echo "Creating app bundle..."

# Build in /tmp to avoid iCloud extended attributes that break codesign
STAGE_DIR=$(mktemp -d)
STAGE_BUNDLE="$STAGE_DIR/$APP_NAME.app"

# Create bundle structure
mkdir -p "$STAGE_BUNDLE/Contents/MacOS"
mkdir -p "$STAGE_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILT_BINARY" "$STAGE_BUNDLE/Contents/MacOS/$BINARY_NAME"

# Copy resource bundle if it exists
RESOURCE_BUNDLE="$("$SWIFT" build -c release --disable-sandbox --show-bin-path)/${BINARY_NAME}_${BINARY_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$STAGE_BUNDLE/Contents/Resources/"
fi

# Generate app icon if not yet built
ICON_FILE="$PROJECT_DIR/Sources/Scriptik/Resources/AppIcon.icns"
if [ ! -f "$ICON_FILE" ]; then
    echo "Generating app icon..."
    "$SWIFT" -Xfrontend -disable-implicit-string-processing-module-import "$SCRIPT_DIR/generate-icon.swift"
fi
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$STAGE_BUNDLE/Contents/Resources/"
fi

# Copy Info.plist to bundle root
cp "$PROJECT_DIR/Sources/Scriptik/Resources/Info.plist" "$STAGE_BUNDLE/Contents/"

# Strip ALL extended attributes (prevents "resource fork" codesign error)
xattr -cr "$STAGE_BUNDLE" 2>/dev/null || true
find "$STAGE_BUNDLE" -exec xattr -c {} \; 2>/dev/null || true

# Codesign with stable identity (preserves Accessibility permission across rebuilds)
# Falls back to ad-hoc if "Scriptik Dev" identity not found
SIGN_IDENTITY="Scriptik Dev"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    SIGN_IDENTITY="-"
fi
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements /dev/stdin \
    "$STAGE_BUNDLE" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Move signed bundle to final location
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"
cp -R "$STAGE_BUNDLE" "$APP_BUNDLE"
rm -rf "$STAGE_DIR"

echo ""
echo "Built: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "To run:"
echo "  open \"$APP_BUNDLE\""
