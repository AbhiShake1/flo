# 01 Parity Matrix

Status legend: `Not Started`, `In Progress`, `Parity`, `Exception`.

| Area | macOS reference | Windows target | Status | Notes |
|---|---|---|---|---|
| Auth bootstrap + restore | `FloController.bootstrap()` | Same startup gating and auth state transitions | In Progress | Core command mapped in `flo-core::controller::FloCommand::Bootstrap`. |
| OAuth login/logout | `login()/logout()` | Browser OAuth + callback + logout parity | In Progress | Port traits present; implementation W3. |
| Global hotkeys | `HotkeyManaging` | Win32 global registration + hold semantics | In Progress | Deterministic hold/conflict semantics implemented in `flo-platform-win::hotkeys`; OS hook wiring pending. |
| Hold-to-talk dictation | `startDictationFromHotkey()/stopDictationFromHotkey()` | Same recorder state machine (`idle/listening/transcribing/injecting/error`) | In Progress | Reducer skeleton implemented. |
| Read selected text | `readSelectedTextFromHotkey()` | UIA first, clipboard fallback | In Progress | Strategy contract in `flo-platform-win::selection`. |
| Elevated target interaction | Injection failures due to privilege mismatch | Prompt to elevate whole app then retry | In Progress | Capability + effect contract implemented. |
| Text injection | `TextInjectionService` | `SendInput` Unicode + replace logic | In Progress | Typed secure-field/integrity/replace path logic implemented in `flo-platform-win::injection`; OS key event plumbing pending. |
| TTS playback | `TTSService` | Native playback with cancel | In Progress | Audio coordinator contracts and interruption semantics are covered in `flo-platform-win::audio`; provider playback wiring pending. |
| Permissions UX | `PermissionsService` + onboarding | Explicit microphone/accessibility/input guidance | In Progress | Permission prompts and settings intents are reducer-complete with acceptance coverage. |
| Floating recorder bar | `FloatingBarManaging` | Bottom-center always-on-top Win32 bar | In Progress | Token-accurate geometry/interaction/motion model implemented in `flo-ui-win32`; native window rendering pending. |
| History persistence | `SessionHistoryStore` | Encrypted local history with retention caps | In Progress | DPAPI-protected encrypted history store + corruption recovery + retention cap implemented in `flo-platform-win::history`. |
| Provider routing/failover | `ProviderRoutingOverrides` behavior | Matching ordering/failover/retry semantics | In Progress | Domain + config contract scaffolded. |
| ZIP packaging | release scripts | Portable ZIP release + updater path | In Progress | Updater feed/stage/rollback logic + `scripts/package-zip.sh` path implemented. |
| MSIX + winget | release infra | GA-gated on code signing readiness | Not Started | Planned W8. |

## FloController public action mapping

Row-by-row action coverage is tracked in `apps/windows/docs/04-controller-action-ledger.md` (69 public actions from macOS baseline).

Any unimplemented behavior is tracked in `apps/windows/docs/parity-tracker.md`.
