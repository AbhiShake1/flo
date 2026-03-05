# Week 00 Status

## Decisions
- Locked architecture to pure Rust + Win32.
- Locked UIA-first read-selected strategy with clipboard fallback.
- Locked whole-app elevation prompt for privileged targets.

## Completed
- Workspace crates and interface scaffolding established.
- Domain parity types and logical key model established.
- Controller commands/effects skeleton established.
- Provider config and platform update/security contracts documented.
- Added strict parity governance docs: `04-controller-action-ledger.md`, `05-ui-parity-spec.md`, `06-error-message-parity.md`.
- Added frozen domain/core/provider contract pass for parity-critical APIs.
- Added reducer coverage for auth, permissions, shortcuts, dictation finalization, history paste-last-transcript, voice prefs, and rewrite presets.
- Started P2 controller/provider parity implementation and integration tests.
- Added provider credential CRUD + saved-credential auth flow reducer paths with parity tests.
- Added permission prompt orchestration reducer paths (`request microphone`, `open settings`, `prompt required permissions`).
- Added provider OAuth callback failure-branch and session refresh lifecycle tests.
- Mapped all 69 action-ledger rows away from `Not Started` into concrete Windows command/query contracts with test evidence references.
- Started P3 platform parity implementation with deterministic unit-tested selection fallback telemetry, injection preflight/send path checks, and elevation decision helpers.
- Added deterministic hotkey conflict/hold-release semantics and audio capture-playback interruption coordinators in `flo-platform-win`.
- Started P4 security/persistence implementation with Credential Manager + DPAPI backend wiring and encrypted history store lifecycle (retention caps + corruption quarantine + key regeneration).
- Added P5 token-accurate `flo-ui-win32` chip geometry/interaction/motion model with 100/125/150 DPI tests.
- Added P6 updater hardening (feed parsing, staged apply metadata, rollback pointer) and release scripts for ZIP packaging + MSIX/winget prep with signing gate.
- Added automated acceptance scenario tests (A1-A6) in `flo-app` as P7 hardening baseline.
- Wired `flo-app` runtime to execute controller effects through concrete service bundle adapters (auth/permissions/prefs/floating-bar/speech/tts).
- Added deterministic runtime coverage for auth restore/login/logout, speech capture transcript handoff, and TTS request propagation.
- Added Win32 shell parity state model in `flo-ui-win32` for tray/menu routing, onboarding permission gating, and DPI-aware shell tokens.
- Added release-readiness artifacts: `07-release-readiness-checklist.md`, `scripts/verify-parity-gates.sh`, and `scripts/release-readiness.sh`.
- Added deterministic runtime fault-injection tests for OAuth, speech capture start/stop, TTS failures, and empty capture behavior in `flo-app`.
- Marked all controller action ledger rows as `Parity` based on existing deterministic reducer/query/provider evidence and updated functional gate status accordingly.
- Marked P0 spec-freeze milestone as `Parity` in the tracker now that governance artifacts are in place and wired into gate scripts.
- Locked all UI surface rows in `05-ui-parity-spec.md` and added deterministic shell token/motion coverage (`flo-ui-win32::shell`) for settings/onboarding/permissions/tray/history-provider surfaces.
- Added exhaustive error-message parity enforcement in `flo-core/tests/error_parity.rs` covering canonical text and trigger mappings.

## Blockers
- None for scaffold stage.

## Risk delta
- R4 (unsigned updater trust model) remains high until signed release channel is available.
