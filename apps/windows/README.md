# flo Windows App

Native Windows implementation plan for flo using pure Rust + Win32.

## Current status

Scaffold complete:
- Rust workspace with domain/core/provider/platform/ui/app crates.
- Port-oriented interfaces modeled after `apps/macos/Sources/AppCore/ServiceProtocols.swift`.
- Event-driven controller skeleton modeled after `apps/macos/Sources/Features/FloController.swift`.
- Milestone, parity, and acceptance docs under `apps/windows/docs`.

## Workspace crates

- `crates/flo-domain`: shared domain models and platform-neutral key model.
- `crates/flo-core`: controller state machine, ports, capability flags.
- `crates/flo-provider`: provider + env config parsing contract.
- `crates/flo-platform-win`: Win32 integration contracts (security, selection, elevation, update).
- `crates/flo-ui-win32`: Win32 shell/view contracts.
- `crates/flo-app`: process entrypoint/composition root.

## Local checks

```bash
cd apps/windows
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```
