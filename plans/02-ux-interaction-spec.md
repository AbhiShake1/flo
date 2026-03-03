# P02 UX Interaction Spec

## Primary Surfaces
- Menu bar item (`flo`) for status and settings.
- Auth window (blocking shell until login).
- Main settings window (hotkeys, history, permissions status).
- Floating recorder bar near bottom center during dictation lifecycle.

## Interaction Flows
### 1) Dictation (Hold-to-talk)
1. User holds `⌥Space`.
2. Floating bar transitions to `Listening` with live level meter.
3. On key release, state changes to `Transcribing`.
4. Result auto-injected into active app.
5. Optional toast: success or failure.

### 2) Read Selected Text
1. User presses `⌥R`.
2. App attempts selected text retrieval from focused app.
3. If selection empty, show toast `No selected text`.
4. If selection exists, transition floating bar to `Speaking` and play output.

### 3) Onboarding
- First-run path:
  1. login required,
  2. permissions checks (Mic, Accessibility/Input Monitoring),
  3. hotkey confirmation.

## UX States
- `idle`, `listening`, `transcribing`, `injecting`, `speaking`, `error`.

## Accessibility
- Keyboard-only operation.
- VoiceOver labels for all controls.
- High-contrast mode compatibility.
