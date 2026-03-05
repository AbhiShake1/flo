# 03 Acceptance Tests

## A1 Dictation hold flow

1. Press hold shortcut.
2. Recorder state transitions to `listening`.
3. Release shortcut.
4. Recorder transitions through `transcribing` then `injecting` then `idle`.
5. Text appears in target app.

Pass criteria: state timeline and injected output match macOS behavior.

## A2 Read-selected flow with fallback

1. Trigger read-selected in a UIA-compatible target.
2. Confirm text is extracted with UIA path.
3. Trigger in a target where UIA fails.
4. Confirm clipboard fallback path extracts text.

Pass criteria: both paths produce spoken output and history entries; fallback is logged.

## A3 Elevated target interaction

1. Launch flo unelevated.
2. Target an elevated app for injection/read-selected.
3. Trigger action.
4. Confirm elevation prompt appears and explains retry path.

Pass criteria: no silent failure; after relaunch elevated, action succeeds.

## A4 Missing permissions gating

1. Start with microphone/accessibility blocked.
2. Trigger dictation and read-selected.
3. Confirm explicit guidance is shown for missing permissions.

Pass criteria: actionable permission guidance and no undefined state.

## A5 Live dictation finalization

1. Set mode `appendOnly`; speak with partial transcripts.
2. Set mode `replaceWithFinal`; repeat.

Pass criteria: behavior matches macOS for both modes.

## A6 Provider failover

1. Configure multi-provider order and thresholds.
2. Force failures in primary provider.
3. Verify retry/fallback sequence and cooldown behavior.

Pass criteria: sequence matches configured policy and parity expectations.
