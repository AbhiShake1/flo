cask "flo" do
  # Managed by scripts/update_cask.sh and .github/workflows/release.yml
  version "0.1.1"
  # Placeholder value replaced by the release workflow PR after tagging.
  sha256 "e74ac675383b6cf45e1bdd97d390e5e3daa6eb3f902f038898d0656b95f946e5"

  url "https://github.com/AbhiShake1/flo/releases/download/v#{version}/FloApp-#{version}-arm64.dmg"
  name "flo"
  desc "Menu bar dictation and read-aloud app for macOS"
  homepage "https://github.com/AbhiShake1/flo"

  depends_on macos: ">= :sequoia"

  app "FloApp.app"

  zap trash: [
    "~/Library/Application Support/flo",
    "~/Library/Preferences/com.flo.app.plist",
  ]
end
