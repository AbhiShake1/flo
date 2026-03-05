# Parity Tracker

Source of truth for Windows strict one-to-one parity gate.

Status legend: `Not Started`, `In Progress`, `Parity`, `Exception`.

## Milestone tracker

| Milestone | Scope | Owner | Status | Exit criteria |
|---|---|---|---|---|
| P0 | Spec freeze and macOS baseline capture | All | In Progress | `04`, `05`, `06` docs locked and signed. |
| P1 | Domain/core/provider/platform contract freeze + reducer harness | Core/Provider | Parity | Contract APIs frozen; reducer coverage spans auth/permissions/shortcuts/dictation/history/voice/routing categories. |
| P2 | Controller/provider behavior parity | Engineer A | In Progress | Deterministic auth/routing/failover tests passing; credential/auth/permission orchestration now covered; action-by-action parity mapping still in progress. |
| P3 | Platform core I/O parity | Engineer B | In Progress | Selection/injection/elevation deterministic unit matrix is green; hotkeys/audio concrete adapters still pending. |
| P4 | Security/persistence parity | Engineer B | Not Started | Credential Manager + DPAPI + corruption recovery pass. |
| P5 | Native Win32 UI parity | Engineer C | Not Started | Side-by-side chip/settings/onboarding parity at 100/125/150 DPI. |
| P6 | Packaging + update paths | Engineer C | Not Started | ZIP install/upgrade/rollback + updater checksum paths pass. |
| P7 | End-to-end parity hardening | All | Not Started | Full parity matrix green, no open exceptions. |
| P8 | Release readiness + soak | All + QA | Not Started | 48h soak complete and launch checklist signed. |

## Gate tracker (release blockers)

| Gate | Rule | Current state | Evidence |
|---|---|---|---|
| Functional gate | Every row in `04-controller-action-ledger.md` has passing automated or scripted evidence. | In Progress | Action ledger no longer has `Not Started` rows; rows are actively mapped with tests and pending parity signoff. |
| Visual gate | Every row in `05-ui-parity-spec.md` passes side-by-side review at 100/125/150 DPI. | Not Started | Chip tokens locked; full-surface capture pending. |
| Error gate | User-facing errors exactly match `06-error-message-parity.md` text and triggers. | In Progress | Canonical table created; enforcement wiring pending. |
| Elevation gate | Privileged target flow prompts, relaunches, retries, and succeeds without silent failure. | In Progress | Elevation integrity/relaunch decision helpers are implemented and unit-tested; Win32 relaunch wiring still pending. |
| Release gate | No tracker row may remain `Not Started`, `In Progress`, or `Exception`. | Not Met | Pre-release state. |

## Strict parity policy

1. `Exception` is temporary only and must include owner, rationale, and expiry date in weekly status doc.
2. Release candidate creation is blocked until every milestone and every gate is `Parity`.
3. Feature flags may control fallback paths, but may not bypass parity gate criteria.
4. All deltas must be recorded weekly in `apps/windows/docs/status/week-XX.md`.
