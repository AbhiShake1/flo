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

## Blockers
- None for scaffold stage.

## Risk delta
- R4 (unsigned updater trust model) remains high until signed release channel is available.
