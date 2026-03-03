# flo

`flo` is a macOS 15+ menu bar app for global dictation and read-aloud shortcuts.
It supports multi-provider key pools and failover routing via `.env.local`.

## Implemented Scope

- Auth-gated app shell with ChatGPT OAuth lifecycle (`loggedOut`, `authenticating`, `loggedIn`, `authError`).
- Provider API-key auth mode (with per-provider key pools) for dictation/read-aloud without OAuth.
- Explicit OAuth blocker mode when OAuth endpoints are unavailable.
- Global shortcut support with configurable bindings, conflict validation, and persistence.
- Hold-to-talk dictation pipeline: `AVAudioEngine` capture -> transcription -> smart paste injection.
- Read-selected-text pipeline: focused selection capture -> provider TTS synthesis/playback.
- Recorder state transitions with floating status bar and live level meter (`idle`, `listening`, `transcribing`, `injecting`, `speaking`, `error`).
- Permission status checks and deep links for Microphone, Accessibility, and Input Monitoring.
- Secure data handling: keychain token storage + encrypted session history at rest + secure-input injection guard.
- Provider endpoint host allowlisting and no-audio-retention default.
- Voice/speed preferences in settings with persistence.
- Dictation rewrite controls (tone + style + custom instructions) with persisted preferences.
- Live dictation typing mode with partial transcript streaming while speaking.
- Onboarding checklist (permissions + hotkey confirmation).
- Feature flags for degraded operation modes.
- Manual update check URL support.

## Project Structure

- `Sources/AppCore`: domain models, protocols, defaults, and shortcut validation.
- `Sources/Infrastructure`: concrete integrations (OAuth, keychain, audio, hotkeys, network, persistence).
- `Sources/Features`: orchestration layer (`AppEnvironment`, `FloController`, shortcut/voice catalogs).
- `Sources/FloApp`: SwiftUI app entrypoint and settings/auth UI shell.
- `Tests/AppCoreTests`: unit tests for core validation logic.
- `Tests/InfrastructureTests`: integration-focused tests for retry policy, host allowlisting, and storage.
- `Tests/FeaturesTests`: controller state/error transition tests with mocked dependencies.
- `.github/workflows/ci.yml`: macOS CI for build and tests.

## Configuration

Environment variables:

- `FLO_AI_PROVIDER_ORDER` (comma-separated failover order, eg. `openai,gemini,openrouter`)
- `FLO_AI_PROVIDER` (`openai` default; used when `FLO_AI_PROVIDER_ORDER` is unset)
- `FLO_OPENAI_API_KEY` / `FLO_OPENAI_API_KEYS` (or `OPENAI_API_KEY`) for OpenAI API-key mode
- `FLO_GEMINI_API_KEY` / `FLO_GEMINI_API_KEYS` (or `GEMINI_API_KEY`) for Gemini API-key mode
- `FLO_OPENROUTER_API_KEY` / `FLO_OPENROUTER_API_KEYS` (or `OPENROUTER_API_KEY`)
- `FLO_GROQ_API_KEY` / `FLO_GROQ_API_KEYS` (or `GROQ_API_KEY`)
- `FLO_XAI_API_KEY` / `FLO_XAI_API_KEYS` (or `XAI_API_KEY`)
- `FLO_DEEPINFRA_API_KEY` / `FLO_DEEPINFRA_API_KEYS` (or `DEEPINFRA_API_KEY`)
- `FLO_TOGETHER_API_KEY` / `FLO_TOGETHER_API_KEYS` (or `TOGETHER_API_KEY`)
- `FLO_PERPLEXITY_API_KEY` / `FLO_PERPLEXITY_API_KEYS` (or `PERPLEXITY_API_KEY`)
- `FLO_CHATGPT_OAUTH_ENABLED` (`true` by default)
- Optional OAuth overrides: `FLO_CHATGPT_AUTH_URL`, `FLO_CHATGPT_TOKEN_URL`, `FLO_CHATGPT_CLIENT_ID`, `FLO_CHATGPT_CLIENT_SECRET`, `FLO_CHATGPT_REDIRECT_URI`, `FLO_CHATGPT_SCOPES`, `FLO_CHATGPT_ORIGINATOR`
- `FLO_OPENAI_TRANSCRIPTION_URL`, `FLO_OPENAI_TTS_URL`
- `FLO_OPENAI_REWRITE_URL`
- `FLO_GEMINI_TRANSCRIPTION_URL`, `FLO_GEMINI_TTS_URL`, `FLO_GEMINI_REWRITE_URL`
- OpenAI-compatible rewrite URLs: `FLO_OPENROUTER_REWRITE_URL`, `FLO_GROQ_REWRITE_URL`, `FLO_XAI_REWRITE_URL`, `FLO_DEEPINFRA_REWRITE_URL`, `FLO_TOGETHER_REWRITE_URL`, `FLO_PERPLEXITY_REWRITE_URL`
- `FLO_TRANSCRIPTION_MODEL`, `FLO_TTS_MODEL`
- `FLO_REWRITE_MODEL`
- Provider-specific model overrides: `FLO_OPENAI_TRANSCRIPTION_MODEL`, `FLO_OPENAI_TTS_MODEL`, `FLO_GEMINI_TRANSCRIPTION_MODEL`, `FLO_GEMINI_TTS_MODEL`
- Provider-specific rewrite model overrides: `FLO_OPENAI_REWRITE_MODEL`, `FLO_GEMINI_REWRITE_MODEL`, `FLO_OPENROUTER_REWRITE_MODEL`, `FLO_GROQ_REWRITE_MODEL`, `FLO_XAI_REWRITE_MODEL`, `FLO_DEEPINFRA_REWRITE_MODEL`, `FLO_TOGETHER_REWRITE_MODEL`, `FLO_PERPLEXITY_REWRITE_MODEL`
- Provider-specific voice overrides: `FLO_OPENAI_TTS_VOICE`, `FLO_GEMINI_TTS_VOICE`, or `FLO_TTS_VOICE`
- Failover policy: `FLO_FAILOVER_ALLOW_CROSS_PROVIDER`, `FLO_FAILOVER_MAX_ATTEMPTS`, `FLO_FAILOVER_FAILURE_THRESHOLD`, `FLO_FAILOVER_COOLDOWN_SECONDS`, `FLO_FAILOVER_ALLOWED_PROVIDERS`
- `FLO_TTS_SPEED`
- `FLO_TTS_CHUNK_SIZE`
- `FLO_HOST_ALLOWLIST` (comma-separated hosts)
- `FLO_RETAIN_AUDIO_DEBUG=true` (optional debug mode)
- `FLO_FEATURE_GLOBAL_HOTKEYS`, `FLO_FEATURE_DICTATION`, `FLO_FEATURE_READ_ALOUD`
- `FLO_MANUAL_UPDATE_URL` (optional release page URL)

Local config files are auto-loaded from the repo root in this order:

1. `.env.local`
2. `.env`

Setup helper:

```bash
./scripts/setup_local_env.sh
```

## Build

```bash
swift build
```

For local app usage with stable macOS Privacy permissions, launch the bundled dev app:

```bash
./scripts/run_dev_app_bundle.sh
```

If permissions keep resetting, use a stable signing identity:

```bash
security find-identity -v -p codesigning
FLO_CODESIGN_IDENTITY="<identity-hash-or-name>" ./scripts/run_dev_app_bundle.sh
```

After permissions are granted, launch without rebuilding:

```bash
./scripts/run_dev_app_bundle.sh --open-only
```

## Test

This toolchain requires explicit test framework flags:

```bash
./scripts/run_tests.sh
```

## Manual Smoke Harness

```bash
./scripts/manual_smoke_harness.sh
```
