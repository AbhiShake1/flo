# Windows Architecture (Spec Baseline)

## Locked constraints

1. Stack: pure Rust + Win32 UI.
2. Parity: functional + visual parity with macOS.
3. OS floor: Windows 10 and Windows 11.
4. Elevated support: whole-app elevation prompt for privileged targets.
5. Selection strategy: UI Automation first, clipboard fallback second.
6. Distribution: ZIP now, MSIX + winget path in v1.
7. Updates: checksum-verified in-app updater path that works before signing keys are available.

## Layering

- `flo-domain`: stable product language and data contracts.
- `flo-core`: deterministic state machine and side-effect intents.
- `flo-provider`: provider/auth/routing config and request policy contracts.
- `flo-platform-win`: Win32/COM/platform implementation boundary.
- `flo-ui-win32`: Win32 shell + rendering contracts.
- `flo-app`: composition, bootstrap, process lifecycle.

All platform side effects stay behind `flo-core::ports` traits.
