#!/usr/bin/env bash
set -euo pipefail

# Create FnSwitch DMG with app + Applications symlink
# Can be run locally or in CI

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="FnSwitch"
APP_DIR="$PROJECT_DIR/build/$APP_NAME.app"
DMG_NAME="FnSwitch-macOS.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"

# Build .app if it doesn't exist
if [ ! -d "$APP_DIR" ]; then
    echo "==> App bundle not found, building..."
    "$SCRIPT_DIR/package-app.sh"
fi

echo "==> Creating DMG..."
STAGING_DIR="$PROJECT_DIR/build/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> DMG created at: $DMG_PATH"
