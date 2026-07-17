#!/usr/bin/env bash
# Build a signed (Developer ID if available) Whisper67.app and pack a .dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$ROOT/Whisper67.xcodeproj/project.pbxproj" 2>/dev/null || true)
# Prefer MARKETING_VERSION from pbxproj
VERSION=$(grep -m1 'MARKETING_VERSION' "$ROOT/Whisper67.xcodeproj/project.pbxproj" | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d ' "')
VERSION=${VERSION:-1.0.0}

DERIVED="$ROOT/build"
APP_NAME="Whisper67"
APP_SRC="$DERIVED/Build/Products/Release/${APP_NAME}.app"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DMG_PATH="$DIST/${APP_NAME}-${VERSION}.dmg"

echo "▸ Building ${APP_NAME} ${VERSION} (Release)…"
rm -rf "$DERIVED"
xcodebuild \
  -project Whisper67.xcodeproj \
  -scheme Whisper67 \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  | tail -20

test -d "$APP_SRC"

ENTITLEMENTS="$ROOT/Whisper67/Whisper67.entitlements"
# Prefer Developer ID Application if present — MUST re-apply entitlements
# (re-signing without --entitlements strips mic access under hardened runtime)
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  echo "▸ Signing with $ID + entitlements"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$ID" "$APP_SRC"
else
  echo "▸ Ad-hoc signing with entitlements (no Developer ID found)"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP_SRC"
fi

echo "▸ codesign verify"
codesign -dv --verbose=2 "$APP_SRC" 2>&1 | head -15

# Stage DMG contents
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP_SRC" "$STAGE/"
# Applications symlink for drag-install
ln -s /Applications "$STAGE/Applications"

# Optional: copy icon for volume
VOL_NAME="Whisper67 ${VERSION}"

echo "▸ Creating DMG…"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Also keep a clean app copy in dist/
rm -rf "$DIST/${APP_NAME}.app"
cp -R "$APP_SRC" "$DIST/${APP_NAME}.app"

# SHA256
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

rm -rf "$STAGE"
echo ""
echo "✅ Done"
echo "   App: $DIST/${APP_NAME}.app"
echo "   DMG: $DMG_PATH"
ls -lh "$DMG_PATH"
