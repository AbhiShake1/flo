#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/create_dmg.sh /path/to/FloApp.app /path/to/output/FloApp.dmg

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-bundle-path> <output-dmg-path>"
  exit 1
fi

APP_BUNDLE_PATH="$1"
OUTPUT_DMG_PATH="$2"

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "App bundle not found: $APP_BUNDLE_PATH"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp -R "$APP_BUNDLE_PATH" "$TMP_DIR/"

hdiutil create \
  -volname "flo" \
  -srcfolder "$TMP_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG_PATH"

echo "DMG created at: $OUTPUT_DMG_PATH"
