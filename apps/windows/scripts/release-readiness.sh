#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-preview}"

case "$MODE" in
  preview)
    GATE_FLAGS=(--allow-in-progress)
    ;;
  strict)
    GATE_FLAGS=()
    ;;
  *)
    echo "Usage: $0 [preview|strict]"
    exit 1
    ;;
esac

echo "==> Running workspace tests"
(
  cd "$ROOT_DIR"
  cargo test
)

echo "==> Verifying parity gates ($MODE)"
"$ROOT_DIR/scripts/verify-parity-gates.sh" "${GATE_FLAGS[@]}"

echo "==> Building release binary"
(
  cd "$ROOT_DIR"
  cargo build --release -p flo-app
)

echo "Release readiness checks finished ($MODE mode)."
