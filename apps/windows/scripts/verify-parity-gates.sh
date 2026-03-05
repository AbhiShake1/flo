#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs"
STRICT=true

if [[ "${1:-}" == "--allow-in-progress" ]]; then
  STRICT=false
fi

fail=0

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required parity artifact: $path"
    fail=1
  fi
}

require_file "$DOCS_DIR/04-controller-action-ledger.md"
require_file "$DOCS_DIR/05-ui-parity-spec.md"
require_file "$DOCS_DIR/06-error-message-parity.md"
require_file "$DOCS_DIR/parity-tracker.md"

if [[ "$STRICT" == true ]]; then
  if rg -n "^\| A[0-9]{2} .* \| (Not Started|In Progress|Exception)\s*\|" "$DOCS_DIR/04-controller-action-ledger.md" >/dev/null; then
    echo "Controller action ledger has non-parity rows:"
    rg -n "^\| A[0-9]{2} .* \| (Not Started|In Progress|Exception)\s*\|" "$DOCS_DIR/04-controller-action-ledger.md"
    fail=1
  fi

  if rg -n "^\| (Main settings shell|Onboarding/login stage flow|Permissions stage|History \\+ provider workbench|Tray/menu shell|Recorder chip \\(bottom-center\\)|In-chip banners \\(error/success\\)).* \| (Needs Capture|Exception)\s*\|" "$DOCS_DIR/05-ui-parity-spec.md" >/dev/null; then
    echo "UI parity spec has unlocked surfaces:"
    rg -n "^\| (Main settings shell|Onboarding/login stage flow|Permissions stage|History \\+ provider workbench|Tray/menu shell|Recorder chip \\(bottom-center\\)|In-chip banners \\(error/success\\)).* \| (Needs Capture|Exception)\s*\|" "$DOCS_DIR/05-ui-parity-spec.md"
    fail=1
  fi

  if rg -n "^\| P[0-9] .* \| (Not Started|In Progress|Exception)\s*\|" "$DOCS_DIR/parity-tracker.md" >/dev/null; then
    echo "Parity tracker milestones are not fully parity:"
    rg -n "^\| P[0-9] .* \| (Not Started|In Progress|Exception)\s*\|" "$DOCS_DIR/parity-tracker.md"
    fail=1
  fi

  if rg -n "^\| (Functional gate|Visual gate|Error gate|Elevation gate|Release gate) .* \| (Not Started|In Progress|Exception|Not Met)\s*\|" "$DOCS_DIR/parity-tracker.md" >/dev/null; then
    echo "Parity tracker release gates are not fully parity:"
    rg -n "^\| (Functional gate|Visual gate|Error gate|Elevation gate|Release gate) .* \| (Not Started|In Progress|Exception|Not Met)\s*\|" "$DOCS_DIR/parity-tracker.md"
    fail=1
  fi
else
  if rg -n "^\|[^|]+\|[^|]+\|[^|]+\|\s*(Exception|Not Started)\s*\|" "$DOCS_DIR/parity-tracker.md" >/dev/null; then
    echo "Parity tracker contains Exception/Not Started rows in non-strict mode."
    rg -n "^\|[^|]+\|[^|]+\|[^|]+\|\s*(Exception|Not Started)\s*\|" "$DOCS_DIR/parity-tracker.md"
    fail=1
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Parity gate verification failed."
  exit 1
fi

if [[ "$STRICT" == true ]]; then
  echo "Strict parity gates passed."
else
  echo "Non-strict parity gates passed (In Progress tolerated)."
fi
