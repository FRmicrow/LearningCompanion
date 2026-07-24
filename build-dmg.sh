#!/usr/bin/env bash
# build-dmg.sh — Build a distributable DMG for ClipboardVocab
# Usage: ./build-dmg.sh
# Output: .build/ClipboardVocab.dmg
set -euo pipefail

APP_NAME="ClipboardVocab"
APP_DIR=".build/${APP_NAME}.app"
STAGING=".build/dmg-staging"
DMG_PATH=".build/${APP_NAME}.dmg"

echo "▶  Building release binary…"
swift build --configuration release

echo "▶  Assembling .app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/${APP_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"

# Substitute the Xcode placeholder so the plist is valid inside the bundle
sed 's/\$(EXECUTABLE_NAME)/'"${APP_NAME}"'/g' \
  "ClipboardVocab/App/Info.plist" > "$APP_DIR/Contents/Info.plist"

# Copy SPM-processed localisation bundle if present
STRINGS_SRC=".build/release/${APP_NAME}_${APP_NAME}.bundle/Contents/Resources/Localizable.strings"
if [ -f "$STRINGS_SRC" ]; then
  cp "$STRINGS_SRC" "$APP_DIR/Contents/Resources/"
fi

echo "▶  Creating DMG…"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -o "$DMG_PATH"

echo "✅  DMG ready: $DMG_PATH  ($(du -sh "$DMG_PATH" | cut -f1))"
