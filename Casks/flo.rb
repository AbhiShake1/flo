cask "flo" do
  # Managed by scripts/update_cask.sh and .github/workflows/release.yml
  version "0.1.2"
  # Placeholder value replaced by the release workflow PR after tagging.
  sha256 "0f20fcebbf47f979354c57c034ec1f9714ca22860b9fe326ea6ec927c315958d"

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
