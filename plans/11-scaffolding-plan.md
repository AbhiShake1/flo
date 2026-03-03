# P11 Scaffolding Plan

## Prerequisites
- P01 through P10 finalized and frozen.

## Project Layout
- Swift package root (`flo`) opened in Xcode for macOS app target behavior.
- Modules:
  - `AppCore` (models/protocols/state)
  - `Infrastructure` (auth/keychain/network/audio/system integrations)
  - `Features` (auth UI, hotkeys, dictation, read-aloud, settings)
  - `FloApp` (entrypoint + composition)

## Initial Tree
```text
flo/
  Package.swift
  README.md
  Sources/
    FloApp/
    AppCore/
    Infrastructure/
    Features/
  Tests/
    AppCoreTests/
    InfrastructureTests/
```

## Wiring
- Dependency injection through `AppEnvironment` container.
- Services behind protocol interfaces from `AppCore`.
