#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/native/NotchMonitor"
BUILD_DIR="$NATIVE_DIR/.build/release"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="Open Island"
EXECUTABLE_NAME="NotchMonitor"
BUNDLE_ID="app.openisland.monitor"
MIN_SYSTEM_VERSION="13.0"
VERSION="${1:-0.1.0}"
DMG_NAME="Open-Island-${VERSION}.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
ICON_SCRIPT="$REPO_ROOT/scripts/generate-app-icon.sh"
ICON_DIR="$DIST_DIR/icon"
ICON_ICNS="$ICON_DIR/OpenIsland.icns"

echo "Building release binary..."
cd "$NATIVE_DIR"
swift build -c release

echo "Preparing app bundle..."
rm -rf "$APP_BUNDLE" "$STAGING_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$STAGING_DIR"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BINARY"
chmod +x "$APP_BINARY"

cp -R "$NATIVE_DIR/Sources/AppRuntime" "$APP_RESOURCES/AppRuntime"

if [ -x "$ICON_SCRIPT" ]; then
  "$ICON_SCRIPT" "$ICON_DIR"
  if [ -f "$ICON_ICNS" ]; then
    cp "$ICON_ICNS" "$APP_RESOURCES/OpenIsland.icns"
  fi
fi

cat > "$APP_CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>OpenIsland</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_SYSTEM_VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Creating DMG staging area..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DIST_DIR/$DMG_NAME"

echo "Creating DMG..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$DMG_NAME"

echo
echo "Done."
echo "App bundle: $APP_BUNDLE"
echo "DMG: $DIST_DIR/$DMG_NAME"
echo
echo "Note:"
echo "1. This build is unsigned."
echo "2. If you want distribution outside your own Mac, add Developer ID signing and notarization."
