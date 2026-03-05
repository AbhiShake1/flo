#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="${1:-2}"
SLEEP_SECONDS="${2:-0}"
OUT_FILE="${3:-$ROOT_DIR/docs/status/soak-latest.md}"

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -lt 1 ]]; then
  echo "RUNS must be a positive integer."
  exit 1
fi

if ! [[ "$SLEEP_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "SLEEP_SECONDS must be a non-negative integer."
  exit 1
fi

start_epoch="$(date +%s)"
start_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$(dirname "$OUT_FILE")"
{
  echo "# Windows Soak Run"
  echo
  echo "- Start (UTC): $start_iso"
  echo "- Planned runs: $RUNS"
  echo "- Interval seconds: $SLEEP_SECONDS"
  echo
  echo "## Iterations"
} > "$OUT_FILE"

for ((i = 1; i <= RUNS; i++)); do
  iter_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Running soak iteration $i/$RUNS..."

  if (cd "$ROOT_DIR" && ./scripts/release-readiness.sh preview >/tmp/flo-soak-$i.log 2>&1); then
    status="PASS"
  else
    status="FAIL"
  fi

  {
    echo "- Iteration $i: $status (UTC $iter_start)"
    echo "  - Command: \`./scripts/release-readiness.sh preview\`"
    echo "  - Log: \`/tmp/flo-soak-$i.log\`"
  } >> "$OUT_FILE"

  if [[ "$status" == "FAIL" ]]; then
    echo "Iteration $i failed; see /tmp/flo-soak-$i.log"
    break
  fi

  if [[ "$i" -lt "$RUNS" ]] && [[ "$SLEEP_SECONDS" -gt 0 ]]; then
    sleep "$SLEEP_SECONDS"
  fi
done

end_epoch="$(date +%s)"
end_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
elapsed_seconds="$((end_epoch - start_epoch))"
elapsed_hours="$(awk "BEGIN { printf \"%.2f\", $elapsed_seconds/3600 }")"

{
  echo
  echo "## Summary"
  echo
  echo "- End (UTC): $end_iso"
  echo "- Elapsed seconds: $elapsed_seconds"
  echo "- Elapsed hours: $elapsed_hours"
  echo "- Note: strict parity requires 48h soak; this script records progress but does not bypass that requirement."
} >> "$OUT_FILE"

echo "Soak report written to $OUT_FILE"
