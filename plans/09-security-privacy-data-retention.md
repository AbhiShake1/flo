# P09 Security, Privacy, and Data Retention

## Data Classes
- Auth secrets: access/refresh tokens.
- User config: hotkeys, voice preferences.
- Session history: transcript metadata and text.

## Storage Rules
- Tokens in keychain only.
- Session history encrypted at rest.
- No raw audio retained after successful transcription unless debugging mode is enabled.

## Privacy Defaults
- Session history enabled.
- Clear history action in settings.
- Log redaction for tokens and personal strings.

## Transport
- HTTPS/TLS for all remote calls.
- Strict host allowlist for OAuth and OpenAI APIs.
