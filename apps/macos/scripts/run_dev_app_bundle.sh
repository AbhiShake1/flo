#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${FLO_BUILD_CONFIG:-debug}"
APP_NAME="FloApp"
APP_BUNDLE_ID="${FLO_BUNDLE_ID:-com.flo.app}"
OUT_DIR="${FLO_DEV_APP_DIR:-$HOME/Applications}"
APP_BUNDLE_PATH="$OUT_DIR/$APP_NAME.app"
BUILD_BIN_PATH="$ROOT_DIR/.build/arm64-apple-macosx/$BUILD_CONFIG/$APP_NAME"
CODESIGN_IDENTITY="${FLO_CODESIGN_IDENTITY:-}"
ADHOC_REQUIREMENT="designated => identifier \"$APP_BUNDLE_ID\""

MODE="build-and-open"
case "${1:-}" in
  --build-only)
    MODE="build-only"
    ;;
  --open-only)
    MODE="open-only"
    ;;
  "")
    ;;
  *)
    echo "Usage: $0 [--build-only|--open-only]"
    exit 1
    ;;
esac

if [[ "$MODE" == "open-only" ]]; then
  if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
    echo "App bundle not found at $APP_BUNDLE_PATH. Run without --open-only once to build it."
    exit 1
  fi
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  open -na "$APP_BUNDLE_PATH"
  echo "Launched existing $APP_NAME.app from $APP_BUNDLE_PATH"
  exit 0
fi

if [[ "$MODE" == "build-only" ]]; then
  SHOULD_OPEN="false"
else
  SHOULD_OPEN="true"
fi

mkdir -p "$OUT_DIR"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  DETECTED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | \
    grep 'Apple Development' | \
    head -n 1 | \
    awk '{print $2}' || true)"
  if [[ -z "$DETECTED_IDENTITY" ]]; then
    DETECTED_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | \
      grep 'Developer ID Application' | \
      head -n 1 | \
      awk '{print $2}' || true)"
  fi
  if [[ -n "$DETECTED_IDENTITY" ]]; then
    CODESIGN_IDENTITY="$DETECTED_IDENTITY"
  fi
fi

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="-"
fi

sign_bundle() {
  local identity="$1"
  if [[ "$identity" == "-" ]]; then
    codesign --force --deep --timestamp=none --requirements "=$ADHOC_REQUIREMENT" --sign "$identity" "$APP_BUNDLE_PATH"
  else
    codesign --force --deep --timestamp=none --sign "$identity" "$APP_BUNDLE_PATH"
  fi
}

echo "[1/4] Building $APP_NAME ($BUILD_CONFIG)"
swift build --package-path "$ROOT_DIR" -c "$BUILD_CONFIG"

if [[ ! -x "$BUILD_BIN_PATH" ]]; then
  echo "Expected executable at: $BUILD_BIN_PATH"
  exit 1
fi

echo "[2/4] Creating app bundle at $APP_BUNDLE_PATH"
rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS"
mkdir -p "$APP_BUNDLE_PATH/Contents/Resources"
cp "$BUILD_BIN_PATH" "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"

for env_file in .env.local .env; do
  if [[ -f "$ROOT_DIR/$env_file" ]]; then
    cp "$ROOT_DIR/$env_file" "$APP_BUNDLE_PATH/Contents/Resources/$env_file"
  fi
done

cat > "$APP_BUNDLE_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>flo</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_ID</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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
EOF

echo "[3/4] Signing bundle with identity: $CODESIGN_IDENTITY"
if ! sign_bundle "$CODESIGN_IDENTITY"; then
  if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    echo "Warning: signing with $CODESIGN_IDENTITY failed; falling back to ad-hoc signing."
    CODESIGN_IDENTITY="-"
    sign_bundle "$CODESIGN_IDENTITY"
  else
    exit 1
  fi
fi

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  echo "Warning: using ad-hoc signature. macOS privacy grants can reset after rebuilds."
  echo "Set FLO_CODESIGN_IDENTITY to a stable identity (Apple Development) for persistent permissions."
fi

echo "[4/4] Ready: $APP_BUNDLE_PATH"
if [[ "$SHOULD_OPEN" == "true" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  open -na "$APP_BUNDLE_PATH"
  echo "Launched $APP_NAME.app"
else
  echo "Build-only mode enabled; app not launched."
fi
