# P01 Product Requirements

## Product Name
`flo`

## Problem
Enable users to speak instead of typing across macOS apps, and read selected text aloud via hotkeys.

## Goals
- Global hold-to-talk dictation with automatic insertion into focused app.
- Global read-selected-text-aloud shortcut.
- Fast interaction via floating recorder bar and status feedback.
- Account-gated functionality: ChatGPT OAuth required to access app features.

## Non-Goals (v1)
- Offline STT or offline TTS.
- API key login UX.
- App Store-constrained build.

## Functional Requirements
1. Launch app into auth-gated shell.
2. Require successful ChatGPT OAuth before feature pages.
3. Support default hotkeys:
   - Hold `⌥Space`: start/stop dictation.
   - Press `⌥R`: read selected text.
4. Allow users to reconfigure both hotkeys.
5. Dictation flow:
   - capture audio,
   - transcribe with OpenAI,
   - inject text into focused target using smart paste strategy.
6. Read-aloud flow:
   - capture selected text,
   - if none: show error,
   - synthesize voice with OpenAI and play.
7. Persist encrypted session history.

## Non-Functional Requirements
- P95 dictation start latency under 150 ms after hotkey hold.
- Reliable injection in common native + browser text inputs.
- Safe token storage in keychain.

## Success Metrics
- Dictation success rate in target apps.
- Read-aloud success rate with valid selection.
- Crash-free session rate.
