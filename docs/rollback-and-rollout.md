# Rollout and Rollback Plan

## Progressive Rollout

1. Start with internal dogfood distribution only.
2. Monitor these metrics per build:
   - dictation success/failure rate
   - read-aloud success/failure rate
   - crash-free session rate
   - secure-input injection failure frequency
3. Promote from internal to external download channel only if no critical regressions are observed for 48 hours.

## Feature Flags (degraded modes)

The following environment flags can disable risky surfaces quickly:

- `FLO_FEATURE_GLOBAL_HOTKEYS`
- `FLO_FEATURE_DICTATION`
- `FLO_FEATURE_READ_ALOUD`

Use these flags to keep the app launchable during incidents while narrowing blast radius.

## Rollback Procedure

1. Stop promoting the current build artifact.
2. Re-publish prior known-good ZIP/DMG (notarized when available).
3. Set feature flags to disable failing flows in the affected build.
4. Publish incident note with impacted features and workaround.
5. Validate rollback by rerunning manual smoke harness and automated tests.
