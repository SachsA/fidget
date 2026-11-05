cask "fidget" do
  version "__VERSION__"
  sha256 "__APP_SHA__"

  url "https://github.com/SachsA/fidget/releases/download/v#{version}/Fidget-#{version}.zip"
  name "Fidget"
  desc "Menu bar app that keeps your Mac awake by nudging the mouse when idle"
  homepage "https://github.com/SachsA/fidget"

  depends_on macos: ">= :ventura"

  app "Fidget.app"

  uninstall quit: "io.github.sachsa.fidget"

  zap trash: "~/Library/Preferences/io.github.sachsa.fidget.plist"

  caveats <<~EOS
    Fidget is not notarized yet. On first launch macOS will refuse to open it:
    go to System Settings > Privacy & Security and click "Open Anyway".

    Then grant Accessibility access when asked:
      System Settings > Privacy & Security > Accessibility
  EOS
end
