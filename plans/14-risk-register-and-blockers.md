# P14 Risk Register and Blockers

## Critical Risks
1. **Third-party ChatGPT OAuth availability**
   - Impact: hard blocker for production auth.
   - Mitigation: adapter-based auth service and explicit blocker mode.
2. **Global shortcut reliability across apps**
   - Impact: degraded UX.
   - Mitigation: robust event monitor + conflict detection + diagnostics.
3. **Permission denial friction**
   - Impact: onboarding drop-off.
   - Mitigation: clear guided permission flows.
4. **Clipboard side effects from smart paste**
   - Impact: user trust/annoyance.
   - Mitigation: atomic clipboard restore and telemetry for failure.

## Operational Risks
- OpenAI endpoint/model changes.
- Audio device instability and interruptions.
- Large selected text TTS request limits.

## Contingency
- Feature flags for degraded modes.
- Progressive rollout with logging and rollback instructions.
