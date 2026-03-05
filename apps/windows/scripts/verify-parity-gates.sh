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

check_table_statuses() {
  local file="$1"
  local allowed_regex="$2"
  local label="$3"

  local status_lines
  status_lines="$(rg -n "^\|.*\|$" "$file" | rg -v "^\d+:\\|[- ]+\\|$|Status legend|---|^$" || true)"
  if [[ -z "$status_lines" ]]; then
    return
  fi

  local violations
  violations="$(printf "%s\n" "$status_lines" | rg -n -v "$allowed_regex" || true)"
  if [[ -n "$violations" ]]; then
    echo "Status violations in $label:"
    printf "%s\n" "$violations"
    fail=1
  fi
}

require_file "$DOCS_DIR/04-controller-action-ledger.md"
require_file "$DOCS_DIR/05-ui-parity-spec.md"
require_file "$DOCS_DIR/06-error-message-parity.md"
require_file "$DOCS_DIR/parity-tracker.md"

if [[ "$STRICT" == true ]]; then
  check_table_statuses \
    "$DOCS_DIR/04-controller-action-ledger.md" \
    "Parity\\s*\\|$" \
    "controller action ledger"
  check_table_statuses \
    "$DOCS_DIR/05-ui-parity-spec.md" \
    "Locked\\s*\\|$" \
    "ui parity spec"
  check_table_statuses \
    "$DOCS_DIR/parity-tracker.md" \
    "Parity\\s*\\|" \
    "parity tracker"
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
