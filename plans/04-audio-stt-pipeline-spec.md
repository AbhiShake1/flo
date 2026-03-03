# P04 Audio and STT Pipeline Spec

## Objective
Convert held audio capture into transcript text with low latency and reliable retries.

## Pipeline
1. Hotkey down -> start AVAudioEngine capture.
2. Buffers written to temporary WAV container.
3. Hotkey up -> finalize file.
4. Upload to OpenAI transcription endpoint.
5. Parse transcript text and confidence metadata.
6. Return `TranscriptResult` to injection layer.

## Failure Handling
- Empty audio: return `noAudio`.
- Network failure: one immediate retry, then fail.
- 429/5xx: exponential backoff within max 2 retries.

## Output
- Normalized transcript string.
- Request id + latency for history entries.
