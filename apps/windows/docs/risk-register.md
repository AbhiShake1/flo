# Risk Register

| ID | Risk | Impact | Mitigation | Owner | Status |
|---|---|---|---|---|---|
| R1 | UIA coverage differs by app/editor | Read-selected parity gaps | Maintain clipboard fallback and app-specific fixtures | Platform | Open |
| R2 | Elevation UX introduces user confusion | Failed injections in admin targets | Detect integrity mismatch and provide explicit relaunch flow | Platform | Open |
| R3 | Win32 input injection blocked in secure fields | Partial feature availability | Add secure-field detection and clear error text | Platform | Open |
| R4 | Unsigned updater trust model | Update adoption friction | SHA-256 verification + staged apply + explicit source URL display | Release | Open |
| R5 | Provider API churn | Runtime regressions | Contract tests + host allowlist + retry policy guardrails | Provider | Open |
| R6 | Audio device variance | Latency and capture failures | Device matrix tests + fallback device strategy | Platform | Open |
