#!/usr/bin/env bash
# Build a Developer ID–signed Whisper67.app, pack a .dmg, optionally notarize + staple.
#
# Notarization (optional but recommended for Gatekeeper):
#   # One-time:
#   xcrun notarytool store-credentials "whisper67-notary" \
#     --apple-id "you@email.com" \
#     --team-id PPPFP5Z7VS \
#     --password "app-specific-password"
#
#   # Then either:
#   export NOTARY_PROFILE=whisper67-notary
#   ./scripts/build_dmg.sh
#
#   # Or pass credentials via env (no profile):
#   export APPLE_ID=you@email.com
#   export APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
#   export APPLE_TEAM_ID=PPPFP5Z7VS
#   ./scripts/build_dmg.sh
#
# Skip notarization:  SKIP_NOTARIZE=1 ./scripts/build_dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=$(grep -m1 'MARKETING_VERSION' "$ROOT/Whisper67.xcodeproj/project.pbxproj" \
  | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d ' "')
VERSION=${VERSION:-1.0.0}

DERIVED="$ROOT/build"
APP_NAME="Whisper67"
APP_SRC="$DERIVED/Build/Products/Release/${APP_NAME}.app"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DMG_PATH="$DIST/${APP_NAME}-${VERSION}.dmg"
ENTITLEMENTS="$ROOT/Whisper67/Whisper67.entitlements"
TEAM_ID="${APPLE_TEAM_ID:-PPPFP5Z7VS}"
NOTARY_PROFILE="${NOTARY_PROFILE:-whisper67-notary}"

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

# Prefer Developer ID Application — MUST re-apply entitlements under hardened runtime
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
codesign --verify --verbose=2 "$APP_SRC" 2>&1 | tail -5 || true

# Stage DMG
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP_SRC" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
VOL_NAME="Whisper67 ${VERSION}"

echo "▸ Creating DMG…"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DIST/${APP_NAME}.app"
cp -R "$APP_SRC" "$DIST/${APP_NAME}.app"
rm -rf "$STAGE"

# ── Notarization ──────────────────────────────────────────────
notarize_dmg() {
  if [[ "${SKIP_NOTARIZE:-}" == "1" ]]; then
    echo "▸ Skipping notarization (SKIP_NOTARIZE=1)"
    return 0
  fi

  # Prefer keychain profile
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "▸ Submitting DMG to Apple notary service (profile: $NOTARY_PROFILE)…"
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "▸ Submitting DMG to Apple notary service (Apple ID: $APPLE_ID)…"
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait
  else
    echo ""
    echo "⚠️  Notarization skipped — no credentials configured."
    echo "   Gatekeeper will show “Apple could not verify…” until you notarize."
    echo ""
    echo "   One-time setup:"
    echo "     xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "       --apple-id \"you@email.com\" \\"
    echo "       --team-id $TEAM_ID \\"
    echo "       --password \"app-specific-password\""
    echo ""
    echo "   Then re-run:  NOTARY_PROFILE=$NOTARY_PROFILE ./scripts/build_dmg.sh"
    return 0
  fi

  echo "▸ Stapling notarization ticket to DMG…"
  xcrun stapler staple "$DMG_PATH"
  # Also staple the app bundle in dist for completeness
  xcrun stapler staple "$DIST/${APP_NAME}.app" 2>/dev/null || true

  echo "▸ Gatekeeper assessment:"
  spctl -a -vv -t open --context context:primary-signature "$DMG_PATH" 2>&1 || true
}

notarize_dmg

shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

echo ""
echo "✅ Done"
echo "   App: $DIST/${APP_NAME}.app"
echo "   DMG: $DMG_PATH"
ls -lh "$DMG_PATH"
