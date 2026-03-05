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

## Build + Sign (Optional Notarize)

1. Export release metadata env vars:
   - `FLO_RELEASE_VERSION` (without `v`, e.g. `0.1.0`)
   - `FLO_BUILD_NUMBER` (integer build number)
2. For non-notarized builds (current CI mode), run:
   - `FLO_NOTARIZE=false ./scripts/notarize_release.sh`
3. For notarized builds, also export:
   - `FLO_APPLE_TEAM_ID`
   - `FLO_APPLE_ID`
   - `FLO_APPLE_APP_SPECIFIC_PASSWORD`
   - `FLO_DEVELOPER_IDENTITY`
4. Then run:
   - `./scripts/notarize_release.sh`
5. Confirm generated artifacts:
   - `FloApp.app`
   - `FloApp-<version>-arm64.zip`
   - `FloApp-<version>-arm64.zip.sha256`
   - `FloApp-<version>-arm64.dmg` + `FloApp-<version>-arm64.dmg.sha256`
6. Verify release gates pass:
   - `spctl --assess --type execute --verbose FloApp.app` (notarized builds only)
   - `codesign --verify --deep --strict --verbose=2 FloApp.app`

## Distribution

1. Push tag `v<version>` to trigger `.github/workflows/release.yml`.
2. Confirm GitHub Release includes DMG and checksum artifacts.
3. Confirm the automated Homebrew cask bump PR is created and targets `main`.
4. Validate the PR cask changes:
   - `HOMEBREW_NO_AUTO_UPDATE=1 brew tap-new local/flo-ci`
   - `mkdir -p "$(brew --repository local/flo-ci)/Casks"`
   - `cp Casks/flo.rb "$(brew --repository local/flo-ci)/Casks/flo.rb"`
   - `HOMEBREW_NO_AUTO_UPDATE=1 brew audit --cask --strict --tap local/flo-ci flo`
   - `HOMEBREW_NO_AUTO_UPDATE=1 brew untap local/flo-ci`
5. Merge the cask bump PR so users can run:
   - `brew upgrade --cask flo`
6. Publish release notes with known risks and rollback plan.
7. Archive signing metadata and, when applicable, notarization logs.
