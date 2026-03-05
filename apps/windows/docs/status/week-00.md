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

## Blockers
- None for scaffold stage.

## Risk delta
- R4 (unsigned updater trust model) remains high until signed release channel is available.
