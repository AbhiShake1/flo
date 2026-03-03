# P05 Selection Read-Aloud Spec

## Objective
Read selected text in current focused app via OpenAI TTS.

## Selection Strategy
1. Trigger copy command against focused app.
2. Read text from pasteboard.
3. If empty -> surface `No selected text` error.
4. Do not fallback to clipboard or manual input in v1.

## TTS Strategy
- OpenAI-only synthesis.
- Configurable voice and speed in settings.
- Stream or download full audio then play using AVFoundation.

## Error Cases
- No selection.
- Selection too long for single request -> chunk and sequence playback.
- Playback device unavailable.
