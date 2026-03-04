cask "flo" do
  # Managed by scripts/update_cask.sh and .github/workflows/release.yml
  version "0.1.0"
  # Placeholder value replaced by the release workflow PR after tagging.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

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
