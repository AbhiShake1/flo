#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.0.0-dev}"
OUT_DIR="${2:-$ROOT_DIR/dist}"
TARGET_DIR="${3:-$ROOT_DIR/target/release}"
BIN_NAME="${4:-flo-app}"

if [[ "$(uname -s)" == "MINGW"* || "$(uname -s)" == "MSYS"* || "$(uname -s)" == "CYGWIN"* || "$(uname -s)" == "Windows_NT" ]]; then
  BIN_FILE="$BIN_NAME.exe"
else
  BIN_FILE="$BIN_NAME"
fi

BIN_PATH="$TARGET_DIR/$BIN_FILE"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Binary not found at $BIN_PATH"
  echo "Build first: (cd $ROOT_DIR && cargo build --release -p $BIN_NAME)"
  exit 1
fi

PACKAGE_ROOT="$OUT_DIR/flo-windows-$VERSION"
rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT"
cp "$BIN_PATH" "$PACKAGE_ROOT/"

cat > "$PACKAGE_ROOT/README.txt" <<README
Flo Windows ZIP package
Version: $VERSION

Contents:
- $BIN_FILE

Launch:
- Double-click $BIN_FILE
README

mkdir -p "$OUT_DIR"
ZIP_PATH="$OUT_DIR/flo-windows-$VERSION.zip"
(
  cd "$OUT_DIR"
  rm -f "$ZIP_PATH"
  zip -r "$(basename "$ZIP_PATH")" "$(basename "$PACKAGE_ROOT")" >/dev/null
)

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$ZIP_PATH" > "$ZIP_PATH.sha256"
else
  echo "No SHA-256 tool found (shasum/sha256sum)."
  exit 1
fi

echo "Created package: $ZIP_PATH"
echo "Checksum: $ZIP_PATH.sha256"
