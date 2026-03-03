cask "flo" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/AbhiShake1/flo/releases/download/v#{version}/FloApp-#{version}-arm64.dmg",
      verified: "github.com/AbhiShake1/flo/"
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
