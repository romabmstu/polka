# Homebrew cask kept in the project itself, so no separate tap repository:
#   brew tap romabmstu/polka https://github.com/romabmstu/polka
#   brew install --cask romabmstu/polka/polka
cask "polka" do
  version :latest
  sha256 :no_check

  url "https://github.com/romabmstu/polka/releases/latest/download/Polka.dmg"
  name "Polka"
  desc "Control center in the MacBook notch: tabs, VPN, music, calendar, translator"
  homepage "https://romabmstu.github.io/polka/"

  # Polka installs its own signed updates.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Polka.app"

  # Polka is not notarized by Apple yet; without this the first launch is
  # blocked by Gatekeeper.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Polka.app"]
  end

  uninstall quit: "io.github.romabmstu.Polka"

  zap trash: [
    "~/Library/Application Support/Polka",
    "~/Library/Preferences/io.github.romabmstu.Polka.plist",
  ]
end
