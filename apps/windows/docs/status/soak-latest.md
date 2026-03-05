# Windows Soak Run

- Start (UTC): 2026-03-05T13:06:24Z
- Planned runs: 2
- Interval seconds: 0

## Iterations
- Iteration 1: PASS (UTC 2026-03-05T13:06:24Z)
  - Command: `./scripts/release-readiness.sh preview`
  - Log: `/tmp/flo-soak-1.log`
- Iteration 2: PASS (UTC 2026-03-05T13:06:27Z)
  - Command: `./scripts/release-readiness.sh preview`
  - Log: `/tmp/flo-soak-2.log`

## Summary

- End (UTC): 2026-03-05T13:06:28Z
- Elapsed seconds: 4
- Elapsed hours: 0.00
- Note: strict parity requires 48h soak; this script records progress but does not bypass that requirement.
