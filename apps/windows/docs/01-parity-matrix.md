# 01 Parity Matrix

Status legend: `Not Started`, `In Progress`, `Parity`, `Exception`.

| Area | macOS reference | Windows target | Status | Notes |
|---|---|---|---|---|
| Auth bootstrap + restore | `FloController.bootstrap()` | Same startup gating and auth state transitions | In Progress | Core command mapped in `flo-core::controller::FloCommand::Bootstrap`. |
| OAuth login/logout | `login()/logout()` | Browser OAuth + callback + logout parity | In Progress | Port traits present; implementation W3. |
| Global hotkeys | `HotkeyManaging` | Win32 global registration + hold semantics | Not Started | Planned W6. |
| Hold-to-talk dictation | `startDictationFromHotkey()/stopDictationFromHotkey()` | Same recorder state machine (`idle/listening/transcribing/injecting/error`) | In Progress | Reducer skeleton implemented. |
| Read selected text | `readSelectedTextFromHotkey()` | UIA first, clipboard fallback | In Progress | Strategy contract in `flo-platform-win::selection`. |
| Elevated target interaction | Injection failures due to privilege mismatch | Prompt to elevate whole app then retry | In Progress | Capability + effect contract implemented. |
| Text injection | `TextInjectionService` | `SendInput` Unicode + replace logic | Not Started | Planned W6. |
| TTS playback | `TTSService` | Native playback with cancel | Not Started | Planned W5. |
| Permissions UX | `PermissionsService` + onboarding | Explicit microphone/accessibility/input guidance | Not Started | Planned W7. |
| Floating recorder bar | `FloatingBarManaging` | Bottom-center always-on-top Win32 bar | Not Started | Planned W7. |
| History persistence | `SessionHistoryStore` | Encrypted local history with retention caps | Not Started | Planned W4. |
| Provider routing/failover | `ProviderRoutingOverrides` behavior | Matching ordering/failover/retry semantics | In Progress | Domain + config contract scaffolded. |
| ZIP packaging | release scripts | Portable ZIP release + updater path | In Progress | Update contract in `flo-platform-win::update`. |
| MSIX + winget | release infra | GA-gated on code signing readiness | Not Started | Planned W8. |

## FloController public action mapping

Row-by-row action coverage is tracked in `apps/windows/docs/04-controller-action-ledger.md` (69 public actions from macOS baseline).

Any unimplemented behavior is tracked in `apps/windows/docs/parity-tracker.md`.
