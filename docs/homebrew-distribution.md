# Homebrew Distribution

## Artifact Contract
Each tagged release (`vMAJOR.MINOR.PATCH`) must publish:
- `FloApp-<version>-arm64.dmg`
- `FloApp-<version>-arm64.dmg.sha256`

## Cask Definition
A cask template is stored at `Casks/flo.rb`.

Before publishing to Homebrew:
1. Set `version` to the target release.
2. Replace `sha256` with the DMG checksum.
3. Ensure the URL points to the GitHub release asset.

## Preferred Publishing Path
1. Submit to `homebrew/cask` first.
2. If rejected or delayed, publish immediately via `AbhiShake1/homebrew-flo` tap.

## Local Validation
Run before opening a cask PR:

```bash
brew style --fix Casks/flo.rb
brew audit --cask --strict Casks/flo.rb
```
