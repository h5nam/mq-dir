cask "mq-dir" do
  version "0.1.0-alpha"
  sha256 "8b6b3a1fdc53314e642cca4feb1d88d7d2e916942ca8b3d50ec56449e635bf90"

  url "https://github.com/h5nam/mq-dir/releases/download/v#{version}/mq-dir-v#{version}.dmg"
  name "mq-dir"
  desc "Quad-pane native macOS file manager"
  homepage "https://github.com/h5nam/mq-dir"

  auto_updates false
  depends_on macos: ">= :sonoma"

  app "mq-dir.app"

  zap trash: [
    "~/Library/Application Support/com.mqdir.app",
    "~/Library/Preferences/com.mqdir.app.plist",
    "~/Library/Saved Application State/com.mqdir.app.savedState",
  ]
end
