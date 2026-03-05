# 02 Feature Contracts

## Core ports (`flo_core::ports`)

The Windows app must satisfy trait contracts equivalent to macOS service protocols:
- `AuthService`
- `HotkeyManaging`
- `SpeechCaptureService`
- `SelectionReaderService`
- `TextInjectionService`
- `TTSService`
- `PermissionsService`
- `FloatingBarManaging`

Rules:
1. `flo-core` must not call Win32 APIs directly.
2. All side effects are represented as controller effects before execution.
3. Selection extraction attempts UIA first and only falls back to clipboard on failure.
4. If integrity mismatch blocks action, controller emits `PromptForElevation` and stops the action until elevated.

## Domain contracts (`flo_domain`)

`flo_domain::types` includes parity-critical types:
- `AuthState`
- `RecorderState`
- `ShortcutBinding`
- `HistoryEntry`
- `DictationRewritePreferences`
- `ProviderRoutingOverrides`

`flo_domain::keys::LogicalKey` is the platform-neutral shortcut identity used by all crates.

## Provider config contract (`flo_provider::config::FloConfiguration`)

Requirements:
1. Parse provider identity/order/credentials from environment.
2. Preserve failover controls and host allowlist values.
3. Preserve rewrite routing overrides shape.
4. Keep OAuth fields explicit and optional.

## Platform contracts (`flo_platform_win`)

- `security::SecretStore`: Credential Manager + DPAPI abstraction boundary.
- `update::UpdateService`: check feed, download artifact, verify SHA-256, stage apply.
- `selection::SelectionReader`: UIA-first behavior contract.
- `elevation::ElevationService`: prompt-to-elevate whole app contract.
