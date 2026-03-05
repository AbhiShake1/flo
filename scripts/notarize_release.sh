#!/usr/bin/env bash
set -euo pipefail

# Build, sign, optionally notarize, and package a flo macOS app bundle.
# Always required env vars:
#   FLO_RELEASE_VERSION (e.g. 0.1.0)
#   FLO_BUILD_NUMBER (e.g. 42)
# Optional env vars:
#   FLO_BUNDLE_ID (default: com.flo.app)
#   FLO_OUTPUT_DIR (default: ./.artifacts)
#   FLO_ENTITLEMENTS_PATH (optional, use only if required)
#   FLO_BUILD_DMG=true to produce DMG output (default: true)
#   FLO_DEVELOPER_IDENTITY (default: ad-hoc signing with "-")
#   FLO_NOTARIZE=true to submit + staple notarization (default: true)
# Required only when FLO_NOTARIZE=true:
#   FLO_APPLE_TEAM_ID
#   FLO_APPLE_ID
#   FLO_APPLE_APP_SPECIFIC_PASSWORD
#   FLO_DEVELOPER_IDENTITY (Developer ID Application certificate)

BUNDLE_ID="${FLO_BUNDLE_ID:-com.flo.app}"
OUTPUT_DIR="${FLO_OUTPUT_DIR:-$(pwd)/.artifacts}"
ENTITLEMENTS_PATH="${FLO_ENTITLEMENTS_PATH:-}"
BUILD_DMG="${FLO_BUILD_DMG:-true}"
NOTARIZE="${FLO_NOTARIZE:-true}"
BUILD_DMG_NORMALIZED="$(printf '%s' "$BUILD_DMG" | tr '[:upper:]' '[:lower:]')"
NOTARIZE_NORMALIZED="$(printf '%s' "$NOTARIZE" | tr '[:upper:]' '[:lower:]')"
APP_NAME="FloApp.app"
RELEASE_VERSION="${FLO_RELEASE_VERSION:-}"
BUILD_NUMBER="${FLO_BUILD_NUMBER:-}"

RELEASE_VERSION="${RELEASE_VERSION#v}"
ARCH="arm64"
ZIP_NAME="FloApp-${RELEASE_VERSION}-${ARCH}.zip"
DMG_NAME="FloApp-${RELEASE_VERSION}-${ARCH}.dmg"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME"

: "${RELEASE_VERSION:?FLO_RELEASE_VERSION is required}"
: "${BUILD_NUMBER:?FLO_BUILD_NUMBER is required}"

if [[ "$NOTARIZE_NORMALIZED" == "true" ]]; then
  : "${FLO_APPLE_TEAM_ID:?FLO_APPLE_TEAM_ID is required when FLO_NOTARIZE=true}"
  : "${FLO_APPLE_ID:?FLO_APPLE_ID is required when FLO_NOTARIZE=true}"
  : "${FLO_APPLE_APP_SPECIFIC_PASSWORD:?FLO_APPLE_APP_SPECIFIC_PASSWORD is required when FLO_NOTARIZE=true}"
  : "${FLO_DEVELOPER_IDENTITY:?FLO_DEVELOPER_IDENTITY is required when FLO_NOTARIZE=true}"
fi

mkdir -p "$OUTPUT_DIR"

echo "[1/6] Building release app bundle"
FLO_OUTPUT_DIR="$OUTPUT_DIR" \
FLO_BUNDLE_ID="$BUNDLE_ID" \
FLO_RELEASE_VERSION="$RELEASE_VERSION" \
FLO_BUILD_NUMBER="$BUILD_NUMBER" \
./scripts/build_release_app_bundle.sh >/dev/null

echo "[2/6] Codesigning app bundle"
if [[ -n "${FLO_DEVELOPER_IDENTITY:-}" ]]; then
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
else
  if [[ -n "$ENTITLEMENTS_PATH" ]]; then
    echo "Warning: FLO_ENTITLEMENTS_PATH is ignored during ad-hoc signing"
  fi
  codesign --force --deep --sign - "$APP_BUNDLE_PATH"
fi

echo "[3/6] Creating release archive"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE_PATH" "$OUTPUT_DIR/$ZIP_NAME"

if [[ "$NOTARIZE_NORMALIZED" == "true" ]]; then
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
else
  echo "[4/6] Skipping notarization (FLO_NOTARIZE=false)"
  echo "[5/6] Skipping stapling (not notarized)"
  echo "[6/6] Verifying signature only"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH"

shasum -a 256 "$OUTPUT_DIR/$ZIP_NAME" > "$OUTPUT_DIR/$ZIP_NAME.sha256"

if [[ "$BUILD_DMG_NORMALIZED" == "true" ]]; then
  ./scripts/create_dmg.sh "$APP_BUNDLE_PATH" "$OUTPUT_DIR/$DMG_NAME"
  shasum -a 256 "$OUTPUT_DIR/$DMG_NAME" > "$OUTPUT_DIR/$DMG_NAME.sha256"
fi

echo "Release artifacts ready in: $OUTPUT_DIR"
echo "Bundle ID: $BUNDLE_ID"
echo "Version: $RELEASE_VERSION ($BUILD_NUMBER)"
echo "Notarized: $NOTARIZE_NORMALIZED"

if [[ "$NOTARIZE_NORMALIZED" != "true" ]]; then
  echo "Note: non-notarized builds may require Gatekeeper bypass on first launch."
fi
