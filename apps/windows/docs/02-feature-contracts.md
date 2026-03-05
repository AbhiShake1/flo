# 02 Feature Contracts (P1 Freeze)

Contract freeze date: 2026-03-05

## Core ports (`flo_core::ports`)

Windows must satisfy port contracts equivalent to macOS protocols while preserving strict parity behavior.

### Required ports

- `AuthService`
- `HotkeyManaging`
- `SpeechCaptureService`
- `SelectionReaderService` (returns `SelectionReadResult { text, method }`)
- `TextInjectionService` (returns structured `TextInjectionFailureReason`)
- `ElevationService` (integrity-level checks + relaunch prompt contract)
- `TTSService`
- `PermissionsService` (includes `open_settings_target(permission_kind)` mapping)
- `FloatingBarManaging` (renders explicit chip model)

### Core invariants

1. `flo-core` does not call Win32 APIs directly.
2. Reducer transitions are deterministic; side effects are represented as `ControllerEffect` values.
3. Selection extraction is UIA-first with clipboard fallback metadata preserved via `SelectionReadMethod`.
4. Injection failures must be typed (`SecureField`, `IntegrityMismatch`, `GenericFailure`) for canonical error mapping.
5. Elevated-target mismatch must produce explicit elevation prompt effect/event flow.

## Domain contracts (`flo_domain`)

Frozen parity types include:

- `FloatingBarState`
- `AppIntegrityLevel`
- `SelectionReadMethod`
- `PlatformErrorCode`
- `SelectionReadResult`
- `TextInjectionFailureReason`

The platform-neutral key model remains `flo_domain::keys::LogicalKey`.

## Controller contracts (`flo_core::controller`)

- Side-effect intents are represented by `ControllerEffect`.
- Side-effect results are represented by `ControllerEvent` (`AuthRestored`, `CaptureStopped`, `SelectionRead`, `InjectionCompleted`, `InjectionFailed`, `ElevatedRelaunchRequested`, `PermissionStatusUpdated`, etc.).
- Live dictation finalization uses deterministic plan output (`InjectDelta`, `ReplaceWithFinal`, `CopyFinalToClipboard`, `Noop`).
- Canonical user message mapping is driven by `PlatformErrorCode`.

## Provider contracts (`flo_provider`)

- OAuth callback parser validates scheme + host allowlist + state + code + originator.
- Routing override merge precedence matches macOS `applyingRoutingOverrides` behavior:
  - override fields win when present;
  - fallback to base config when absent;
  - provider order always non-empty.
- Failover evaluator outputs deterministic attempt plan (`provider`, `credential_index`, sequence number).

## Platform contracts (`flo_platform_win`)

- `security`: Credential Manager + DPAPI abstraction boundary.
- `selection`: UIA-first + clipboard fallback strategy with method tagging.
- `injection`: structured failure reasons and secure-field/integrity mismatch signaling.
- `elevation`: whole-app UAC relaunch contract with integrity-level semantics.
- `update`: feed check, download, checksum verify, stage apply.
