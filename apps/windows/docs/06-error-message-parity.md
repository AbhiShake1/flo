# 06 Error Message Parity

This document defines canonical Windows user-facing error/status strings and trigger conditions for strict parity with macOS controller behavior.

Reference sources:
- `apps/macos/Sources/AppCore/CoreTypes.swift` (`FloError.errorDescription`)
- `apps/macos/Sources/Features/FloController.swift` (status and fallback notices)

## Canonical message table

| Code | Canonical message | Trigger condition |
|---|---|---|
| `oauth.missing_configuration` | `ChatGPT OAuth configuration is missing.` | OAuth login attempted while OAuth config is absent. |
| `oauth.failed` | `OAuth failed: {message}` | OAuth browser/callback/token exchange errors. |
| `oauth.state_mismatch` | `OAuth failed: State mismatch` | Callback includes a `state` that differs from expected value. |
| `oauth.authorization_code_missing` | `OAuth failed: Authorization code missing` | Callback cannot provide a usable `code`. |
| `auth.unauthorized` | `You are not authenticated.` | Session missing/expired and refresh unavailable. |
| `audio.empty_capture` | `No audio was captured.` | Stop capture returns empty/invalid audio payload. |
| `selection.none` | `No selected text.` | UIA and clipboard fallback both fail to provide text. |
| `injection.generic_failed` | `Failed to inject transcript into the focused app.` | Injection/replacement fails for non-secure generic reasons. |
| `injection.secure_input_active` | `Injection blocked while secure input is active.` | Target indicates secure field/input active. |
| `feature.disabled` | `{feature} is disabled by configuration.` | Feature gate disables dictation/read-aloud/hotkeys. |
| `permission.denied` | `Permission denied: {permission}.` | Missing required permission for operation. |
| `network.error` | `Network error: {message}` | Provider/network request failures surfaced to user. |
| `persistence.error` | `Persistence error: {message}` | Storage/serialization/history/keychain failures. |
| `elevation.required_target` | `The focused app requires elevated mode. Please relaunch flo as admin.` | Read/inject against elevated target while flo is unelevated. |
| `dictation.fallback.clipboard_copied` | `Couldn't type transcript. Copied to clipboard instead.` | Injection fallback path succeeded by clipboard copy. |
| `dictation.fallback.clipboard_failed` | `Couldn't type transcript and could not copy to clipboard.` | Injection fallback path fails fully. |
| `dictation.live_typing_paused` | `Live typing paused: {message}. Final transcript will still complete.` | Live delta injection fails mid-capture. |
| `dictation.live_finalization_append` | `Live transcript differed from final model output. Final transcript copied to clipboard.` | Append-only reconciliation cannot derive suffix and copy succeeds. |
| `dictation.live_finalization_append_copy_failed` | `Live transcript differed from final model output. Could not copy final transcript to clipboard.` | Append-only reconciliation cannot derive suffix and copy fails. |
| `dictation.live_finalization_replace` | `Replaced live draft with final transcript.` | Replace-with-final mode reconciles differing final transcript. |
| `read_aloud.canceled` | `Read-aloud canceled.` | Speaking task canceled by user/action conflict. |
| `read_aloud.completed` | `Read-aloud completed.` | Speaking task completes successfully. |
| `voice_preview.busy` | `Wait for the current action to finish, then try voice preview again.` | Voice preview triggered while recorder is not idle. |

## Trigger precedence rules

1. Prefer specific secure-field/permission/elevation messages over generic injection fallback text.
2. If clipboard fallback succeeds after an injection failure, show clipboard fallback message (not generic injection failed).
3. OAuth callback validation errors (`state`, missing `code`, blocked host) always map to `oauth.*` codes.
4. During live dictation, transient partial reconciliation mismatches do not emit an error; only finalization mismatches emit `dictation.live_finalization_*` notices.
5. For failed read-selected attempts, surface `selection.none` only after both UIA and clipboard fallback are exhausted.

## Localization and formatting constraints

1. Punctuation and capitalization must match canonical messages exactly.
2. Placeholder values (`{message}`, `{permission}`, `{feature}`) preserve source text without extra prefixes.
3. Windows must not introduce alternative phrasing for listed codes.
4. Any newly introduced user-visible message must be added here before merge.
