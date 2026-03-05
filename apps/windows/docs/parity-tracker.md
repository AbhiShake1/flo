# Parity Tracker

Source of truth for Windows strict one-to-one parity gate.

Status legend: `Not Started`, `In Progress`, `Parity`, `Exception`.

## Milestone tracker

| Milestone | Scope | Owner | Status | Exit criteria |
|---|---|---|---|---|
| P0 | Spec freeze and macOS baseline capture | All | Parity | `04`, `05`, `06` docs exist as locked parity artifacts for implementation and gate checks. |
| P1 | Domain/core/provider/platform contract freeze + reducer harness | Core/Provider | Parity | Contract APIs frozen; reducer coverage spans auth/permissions/shortcuts/dictation/history/voice/routing categories. |
| P2 | Controller/provider behavior parity | Engineer A | Parity | Deterministic auth/routing/failover tests are passing and the action ledger rows are mapped to parity-backed reducer/query/provider coverage. |
| P3 | Platform core I/O parity | Engineer B | Parity | Hotkeys/audio/selection/injection/elevation paths are covered with deterministic tests, app runtime wiring, and relaunch handoff persistence + retry acceptance coverage. |
| P4 | Security/persistence parity | Engineer B | Parity | Credential Manager + DPAPI backends and encrypted history lifecycle (retention/corruption recovery/key regeneration) are covered by deterministic tests. |
| P5 | Native Win32 UI parity | Engineer C | Parity | Token/motion/interaction parity now covers recorder chip plus settings/onboarding/permissions/tray/history-provider shell surfaces with deterministic DPI tests and locked spec rows. |
| P6 | Packaging + update paths | Engineer C | Parity | Feed parsing, checksum validation, staged apply + rollback pointer, ZIP packaging script, MSIX/winget prep script, and release readiness gate scripts are implemented and exercised in preview readiness runs. |
| P7 | End-to-end parity hardening | All | Parity | Acceptance scenarios A1-A7 plus deterministic runtime fault-injection coverage (oauth/audio/capture/tts/selection/injection/elevation) are automated and green in `flo-app`. |
| P8 | Release readiness + soak | All + QA | In Progress | Release checklist (`07-release-readiness-checklist.md`) and gate scripts (`scripts/release-readiness.sh`, `scripts/verify-parity-gates.sh`) are in place; 48h soak and strict-gate signoff pending. |

## Gate tracker (release blockers)

| Gate | Rule | Current state | Evidence |
|---|---|---|---|
| Functional gate | Every row in `04-controller-action-ledger.md` has passing automated or scripted evidence. | Parity | Action ledger rows are marked `Parity` with deterministic reducer/query/provider test evidence. |
| Visual gate | Every row in `05-ui-parity-spec.md` passes side-by-side review at 100/125/150 DPI. | Parity | `05-ui-parity-spec.md` surface rows are locked and backed by deterministic DPI assertions in `flo-ui-win32` shell + chip tests. |
| Error gate | User-facing errors exactly match `06-error-message-parity.md` text and triggers. | Parity | `flo-core/tests/error_parity.rs` enforces canonical message text and injection/error trigger mappings against `PlatformErrorCode`. |
| Elevation gate | Privileged target flow prompts, relaunches, retries, and succeeds without silent failure. | Parity | Elevation decision + relaunch handoff persistence is covered in `flo-platform-win`, and prompt→relaunch→retry behavior is enforced by `flo-app` acceptance test A7. |
| Release gate | No tracker row may remain `Not Started`, `In Progress`, or `Exception`. | Not Met | Pre-release state. |

## Strict parity policy

1. `Exception` is temporary only and must include owner, rationale, and expiry date in weekly status doc.
2. Release candidate creation is blocked until every milestone and every gate is `Parity`.
3. Feature flags may control fallback paths, but may not bypass parity gate criteria.
4. All deltas must be recorded weekly in `apps/windows/docs/status/week-XX.md`.
