# flo Release Checklist

## Pre-Release

1. Run tests:
   - `./scripts/run_tests.sh`
2. Run manual smoke harness:
   - `./scripts/manual_smoke_harness.sh`
3. Confirm OAuth and OpenAI endpoint env configuration matches production.
4. Verify host allowlist entries include only required domains.
5. Verify rollout and rollback notes in `docs/rollback-and-rollout.md`.
6. Confirm release tag uses semver format `vMAJOR.MINOR.PATCH`.

## Build + Notarize

1. Export Apple credentials, signing identity, and release metadata env vars:
   - `FLO_RELEASE_VERSION` (without `v`, e.g. `0.1.0`)
   - `FLO_BUILD_NUMBER` (integer build number)
   - `FLO_APPLE_TEAM_ID`
   - `FLO_APPLE_ID`
   - `FLO_APPLE_APP_SPECIFIC_PASSWORD`
   - `FLO_DEVELOPER_IDENTITY`
2. Run:
   - `./scripts/notarize_release.sh`
3. Confirm generated artifacts:
   - `FloApp.app`
   - `FloApp-<version>-arm64.zip`
   - `FloApp-<version>-arm64.zip.sha256`
   - `FloApp-<version>-arm64.dmg` + `FloApp-<version>-arm64.dmg.sha256`
4. Verify release gates pass:
   - `spctl --assess --type execute --verbose FloApp.app`
   - `codesign --verify --deep --strict --verbose=2 FloApp.app`

## Distribution

1. Push tag `v<version>` to trigger `.github/workflows/release.yml`.
2. Confirm GitHub Release includes DMG and checksum artifacts.
3. Publish release notes with known risks and rollback plan.
4. Submit/update Homebrew cask and validate:
   - `brew audit --cask --strict`
5. Archive notarization logs and signing metadata.
