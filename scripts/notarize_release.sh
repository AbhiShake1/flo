#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, and staple a flo macOS app bundle.
# Required env vars:
#   FLO_APPLE_TEAM_ID
#   FLO_APPLE_ID
#   FLO_APPLE_APP_SPECIFIC_PASSWORD
#   FLO_DEVELOPER_IDENTITY
# Optional:
#   FLO_BUNDLE_ID (default: com.flo.app)
#   FLO_OUTPUT_DIR (default: ./.artifacts)
#   FLO_ENTITLEMENTS_PATH (optional, use only if required)
#   FLO_BUILD_DMG=true to produce DMG after notarization

BUNDLE_ID="${FLO_BUNDLE_ID:-com.flo.app}"
OUTPUT_DIR="${FLO_OUTPUT_DIR:-$(pwd)/.artifacts}"
ENTITLEMENTS_PATH="${FLO_ENTITLEMENTS_PATH:-}"
BUILD_DMG="${FLO_BUILD_DMG:-false}"
APP_NAME="FloApp.app"
ZIP_NAME="FloApp.zip"
DMG_NAME="FloApp.dmg"

: "${FLO_APPLE_TEAM_ID:?FLO_APPLE_TEAM_ID is required}"
: "${FLO_APPLE_ID:?FLO_APPLE_ID is required}"
: "${FLO_APPLE_APP_SPECIFIC_PASSWORD:?FLO_APPLE_APP_SPECIFIC_PASSWORD is required}"
: "${FLO_DEVELOPER_IDENTITY:?FLO_DEVELOPER_IDENTITY is required}"

mkdir -p "$OUTPUT_DIR"

echo "[1/6] Building release app"
swift build -c release

BUILD_APP_PATH="$(pwd)/.build/arm64-apple-macosx/release/${APP_NAME}"
if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "Expected app bundle at $BUILD_APP_PATH"
  exit 1
fi

cp -R "$BUILD_APP_PATH" "$OUTPUT_DIR/$APP_NAME"

echo "[2/6] Codesigning app bundle"
if [[ -n "$ENTITLEMENTS_PATH" ]]; then
  codesign --force --options runtime --timestamp --deep \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign "$FLO_DEVELOPER_IDENTITY" \
    "$OUTPUT_DIR/$APP_NAME"
else
  codesign --force --options runtime --timestamp --deep \
    --sign "$FLO_DEVELOPER_IDENTITY" \
    "$OUTPUT_DIR/$APP_NAME"
fi

echo "[3/6] Creating notarization archive"
/usr/bin/ditto -c -k --keepParent "$OUTPUT_DIR/$APP_NAME" "$OUTPUT_DIR/$ZIP_NAME"

echo "[4/6] Submitting for notarization"
xcrun notarytool submit "$OUTPUT_DIR/$ZIP_NAME" \
  --apple-id "$FLO_APPLE_ID" \
  --password "$FLO_APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$FLO_APPLE_TEAM_ID" \
  --wait

echo "[5/6] Stapling notarization ticket"
xcrun stapler staple "$OUTPUT_DIR/$APP_NAME"

echo "[6/6] Verifying signature and notarization"
spctl --assess --type execute --verbose "$OUTPUT_DIR/$APP_NAME"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_DIR/$APP_NAME"

shasum -a 256 "$OUTPUT_DIR/$ZIP_NAME" > "$OUTPUT_DIR/$ZIP_NAME.sha256"

if [[ "${BUILD_DMG,,}" == "true" ]]; then
  ./scripts/create_dmg.sh "$OUTPUT_DIR/$APP_NAME" "$OUTPUT_DIR/$DMG_NAME"
  shasum -a 256 "$OUTPUT_DIR/$DMG_NAME" > "$OUTPUT_DIR/$DMG_NAME.sha256"
fi

echo "Release artifacts ready in: $OUTPUT_DIR"
echo "Bundle ID: $BUNDLE_ID"
