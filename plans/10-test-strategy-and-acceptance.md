# P10 Test Strategy and Acceptance

## Test Layers
- Unit tests: stores, parsers, config mapping, error transitions.
- Integration tests: auth lifecycle, STT and TTS client request building, history persistence.
- UI/smoke tests: login gate, permissions UI, hotkey flows (manual harness).

## Acceptance Scenarios
1. Unauthenticated launch cannot access core screens.
2. OAuth callback success unlocks app.
3. Hold `⌥Space` records and inserts transcript.
4. Press `⌥R` reads selected text aloud.
5. No selection surfaces explicit error.
6. Hotkey reconfiguration persists and avoids conflicts.
7. Session history stored and can be cleared.

## Release Gate
- All critical path tests pass.
- Manual checklist on macOS 15 latest patch.
