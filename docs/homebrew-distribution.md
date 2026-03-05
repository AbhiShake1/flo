# Homebrew Distribution

## Artifact Contract
Each tagged release (`vMAJOR.MINOR.PATCH`) must publish:
- `FloApp-<version>-arm64.dmg`
- `FloApp-<version>-arm64.dmg.sha256`

## Cask Definition
A tap-ready cask is stored at `Casks/flo.rb`.
This repository can be tapped directly as `AbhiShake1/flo`.

## CI Automation
Tagging `v<version>` triggers `.github/workflows/release.yml`, which:
1. Builds release artifacts (currently non-notarized).
2. Publishes the GitHub Release.
3. Opens a PR that bumps `Casks/flo.rb` version + `sha256` using `scripts/update_cask.sh`.

After that PR is merged, Homebrew users can upgrade with:

```bash
brew upgrade --cask flo
```

## End-User Install Commands

```bash
brew tap AbhiShake1/flo https://github.com/AbhiShake1/flo
brew install --cask --no-quarantine flo
```

For first-time bootstrap, merge the first automated cask bump PR after your
initial tagged release before asking users to run install.

## Maintainer Commands

```bash
# trigger release + automated cask bump PR
git tag v0.1.0
git push origin v0.1.0
```

## Local Validation
Run before opening or merging a cask bump PR:

```bash
./scripts/update_cask.sh 0.1.0 <dmg-sha256>
HOMEBREW_NO_AUTO_UPDATE=1 brew tap-new local/flo-ci
mkdir -p "$(brew --repository local/flo-ci)/Casks"
cp Casks/flo.rb "$(brew --repository local/flo-ci)/Casks/flo.rb"
HOMEBREW_NO_AUTO_UPDATE=1 brew audit --cask --strict --tap local/flo-ci flo
HOMEBREW_NO_AUTO_UPDATE=1 brew untap local/flo-ci
```
