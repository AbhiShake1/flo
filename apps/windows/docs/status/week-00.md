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

## Blockers
- None for scaffold stage.

## Risk delta
- R4 (unsigned updater trust model) remains high until signed release channel is available.
