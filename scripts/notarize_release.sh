#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, and staple a flo macOS app bundle.
# Required env vars:
#   FLO_APPLE_TEAM_ID
#   FLO_APPLE_ID
#   FLO_APPLE_APP_SPECIFIC_PASSWORD
#   FLO_DEVELOPER_IDENTITY
#   FLO_RELEASE_VERSION (e.g. 0.1.0)
#   FLO_BUILD_NUMBER (e.g. 42)
# Optional:
#   FLO_BUNDLE_ID (default: com.flo.app)
#   FLO_OUTPUT_DIR (default: ./.artifacts)
#   FLO_ENTITLEMENTS_PATH (optional, use only if required)
#   FLO_BUILD_DMG=true to produce DMG after notarization (default: true)

BUNDLE_ID="${FLO_BUNDLE_ID:-com.flo.app}"
OUTPUT_DIR="${FLO_OUTPUT_DIR:-$(pwd)/.artifacts}"
ENTITLEMENTS_PATH="${FLO_ENTITLEMENTS_PATH:-}"
BUILD_DMG="${FLO_BUILD_DMG:-true}"
APP_NAME="FloApp.app"
RELEASE_VERSION="${FLO_RELEASE_VERSION:-}"
BUILD_NUMBER="${FLO_BUILD_NUMBER:-}"

RELEASE_VERSION="${RELEASE_VERSION#v}"
ARCH="arm64"
ZIP_NAME="FloApp-${RELEASE_VERSION}-${ARCH}.zip"
DMG_NAME="FloApp-${RELEASE_VERSION}-${ARCH}.dmg"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME"

: "${FLO_APPLE_TEAM_ID:?FLO_APPLE_TEAM_ID is required}"
: "${FLO_APPLE_ID:?FLO_APPLE_ID is required}"
: "${FLO_APPLE_APP_SPECIFIC_PASSWORD:?FLO_APPLE_APP_SPECIFIC_PASSWORD is required}"
: "${FLO_DEVELOPER_IDENTITY:?FLO_DEVELOPER_IDENTITY is required}"
: "${RELEASE_VERSION:?FLO_RELEASE_VERSION is required}"
: "${BUILD_NUMBER:?FLO_BUILD_NUMBER is required}"

mkdir -p "$OUTPUT_DIR"

echo "[1/6] Building release app bundle"
FLO_OUTPUT_DIR="$OUTPUT_DIR" \
FLO_BUNDLE_ID="$BUNDLE_ID" \
FLO_RELEASE_VERSION="$RELEASE_VERSION" \
FLO_BUILD_NUMBER="$BUILD_NUMBER" \
./scripts/build_release_app_bundle.sh >/dev/null

echo "[2/6] Codesigning app bundle"
if [[ -n "$ENTITLEMENTS_PATH" ]]; then
  codesign --force --options runtime --timestamp --deep \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign "$FLO_DEVELOPER_IDENTITY" \
    "$APP_BUNDLE_PATH"
else
  codesign --force --options runtime --timestamp --deep \
    --sign "$FLO_DEVELOPER_IDENTITY" \
    "$APP_BUNDLE_PATH"
fi

echo "[3/6] Creating notarization archive"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE_PATH" "$OUTPUT_DIR/$ZIP_NAME"

echo "[4/6] Submitting for notarization"
xcrun notarytool submit "$OUTPUT_DIR/$ZIP_NAME" \
  --apple-id "$FLO_APPLE_ID" \
  --password "$FLO_APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$FLO_APPLE_TEAM_ID" \
  --wait

echo "[5/6] Stapling notarization ticket"
xcrun stapler staple "$APP_BUNDLE_PATH"

echo "[6/6] Verifying signature and notarization"
spctl --assess --type execute --verbose "$APP_BUNDLE_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH"

shasum -a 256 "$OUTPUT_DIR/$ZIP_NAME" > "$OUTPUT_DIR/$ZIP_NAME.sha256"

if [[ "${BUILD_DMG,,}" == "true" ]]; then
  ./scripts/create_dmg.sh "$APP_BUNDLE_PATH" "$OUTPUT_DIR/$DMG_NAME"
  shasum -a 256 "$OUTPUT_DIR/$DMG_NAME" > "$OUTPUT_DIR/$DMG_NAME.sha256"
fi

echo "Release artifacts ready in: $OUTPUT_DIR"
echo "Bundle ID: $BUNDLE_ID"
echo "Version: $RELEASE_VERSION ($BUILD_NUMBER)"
