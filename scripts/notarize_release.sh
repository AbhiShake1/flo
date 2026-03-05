#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT_DIR/apps/macos/scripts/notarize_release.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "Missing target script: $TARGET"
  exit 1
fi

exec "$TARGET" "$@"
