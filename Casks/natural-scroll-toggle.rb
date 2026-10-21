cask "natural-scroll-toggle" do
  version "0.2.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/matej-basic/natural-scroll-toggle/releases/download/v#{version}/NaturalScrollToggle-#{version}.zip"
  name "Natural Scroll Toggle"
  desc "Menu bar app that switches natural scrolling for mouse and trackpad"
  homepage "https://github.com/matej-basic/natural-scroll-toggle"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "NaturalScrollToggle.app"

  # Ad-hoc signed, not notarized: drop the quarantine flag Homebrew sets on cask
  # downloads, otherwise Gatekeeper blocks the first launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/NaturalScrollToggle.app"]
  end

  zap trash: "~/Library/Preferences/com.matejbasic.NaturalScrollToggle.plist"
end
