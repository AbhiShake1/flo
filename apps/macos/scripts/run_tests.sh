#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

swift test \
  --package-path "$APP_ROOT" \
  --enable-xctest \
  --enable-swift-testing \
  "$@"
