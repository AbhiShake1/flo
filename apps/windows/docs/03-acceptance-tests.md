# 03 Acceptance Tests

Automated baseline coverage: `apps/windows/crates/flo-app/src/acceptance.rs`.

## A1 Dictation hold flow

1. Press hold shortcut.
2. Recorder state transitions to `listening`.
3. Release shortcut.
4. Recorder transitions through `transcribing` then `injecting` then `idle`.
5. Text appears in target app.

Pass criteria: state timeline and injected output match macOS behavior.
Evidence: `acceptance_a1_dictation_hold_flow`.

## A2 Read-selected flow with fallback

1. Trigger read-selected in a UIA-compatible target.
2. Confirm text is extracted with UIA path.
3. Trigger in a target where UIA fails.
4. Confirm clipboard fallback path extracts text.

Pass criteria: both paths produce spoken output and history entries; fallback is logged.
Evidence: `acceptance_a2_read_selected_uia_and_clipboard_fallback`.

## A3 Elevated target interaction

1. Launch flo unelevated.
2. Target an elevated app for injection/read-selected.
3. Trigger action.
4. Confirm elevation prompt appears and explains retry path.

Pass criteria: no silent failure; after relaunch elevated, action succeeds.
Evidence: `acceptance_a3_elevated_target_flow_requests_relaunch`.

## A4 Missing permissions gating

1. Start with microphone/accessibility blocked.
2. Trigger dictation and read-selected.
3. Confirm explicit guidance is shown for missing permissions.

Pass criteria: actionable permission guidance and no undefined state.
Evidence: `acceptance_a4_missing_permissions_prompt_only_missing`.

## A5 Live dictation finalization

1. Set mode `appendOnly`; speak with partial transcripts.
2. Set mode `replaceWithFinal`; repeat.

Pass criteria: behavior matches macOS for both modes.
Evidence: `acceptance_a5_live_finalization_modes`.

## A6 Provider failover

1. Configure multi-provider order and thresholds.
2. Force failures in primary provider.
3. Verify retry/fallback sequence and cooldown behavior.

Pass criteria: sequence matches configured policy and parity expectations.
Evidence: `acceptance_a6_provider_failover_order`.
