# flo Release Checklist

## Pre-Release

1. Run tests:
   - `./scripts/run_tests.sh`
2. Run manual smoke harness:
   - `./scripts/manual_smoke_harness.sh`
3. Confirm OAuth and OpenAI endpoint env configuration matches production.
4. Verify host allowlist entries include only required domains.
5. Verify rollout and rollback notes in `docs/rollback-and-rollout.md`.

## Build + Notarize

1. Export Apple credentials and signing identity env vars.
2. Run:
   - `./scripts/notarize_release.sh`
3. Confirm generated artifacts:
   - `FloApp.app`
   - `FloApp.zip`
   - `FloApp.zip.sha256`
   - optional: `FloApp.dmg` + `FloApp.dmg.sha256` (if `FLO_BUILD_DMG=true`)

## Distribution

1. Publish ZIP and checksum to release channel.
2. Publish release notes with known risks and rollback plan.
3. Archive notarization logs and signing metadata.
