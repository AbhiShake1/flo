#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
APP_NAME="FloApp"
APP_DISPLAY_NAME="flo"
BUNDLE_ID="${FLO_BUNDLE_ID:-com.flo.app}"
OUTPUT_DIR="${FLO_OUTPUT_DIR:-$REPO_ROOT/.artifacts}"
RELEASE_VERSION="${FLO_RELEASE_VERSION:-}"
BUILD_NUMBER="${FLO_BUILD_NUMBER:-}"

RELEASE_VERSION="${RELEASE_VERSION#v}"

: "${RELEASE_VERSION:?FLO_RELEASE_VERSION is required (example: 0.1.0)}"
: "${BUILD_NUMBER:?FLO_BUILD_NUMBER is required (example: 1)}"

mkdir -p "$OUTPUT_DIR"

echo "[1/4] Building release binary"
(
  cd "$ROOT_DIR"
  swift build -c release
)

BUILD_BIN_PATH="$ROOT_DIR/.build/arm64-apple-macosx/release/$APP_NAME"
if [[ ! -x "$BUILD_BIN_PATH" ]]; then
  BUILD_BIN_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/release/$APP_NAME" | head -n 1 || true)"
fi

if [[ -z "$BUILD_BIN_PATH" || ! -x "$BUILD_BIN_PATH" ]]; then
  echo "Unable to locate compiled binary for $APP_NAME"
  exit 1
fi

APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_NAME.app"

echo "[2/4] Creating app bundle at $APP_BUNDLE_PATH"
rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS"
mkdir -p "$APP_BUNDLE_PATH/Contents/Resources"
cp "$BUILD_BIN_PATH" "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"

echo "[3/4] Writing Info.plist metadata"
cat > "$APP_BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$RELEASE_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>flo needs microphone access for dictation capture.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>flo uses speech recognition to stream live transcript while you speak.</string>
</dict>
</plist>
PLIST

echo "[4/4] App bundle ready"
echo "$APP_BUNDLE_PATH"
