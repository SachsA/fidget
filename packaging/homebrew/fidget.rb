class Fidget < Formula
  desc "Keep your Mac awake and your status green by nudging the mouse when idle"
  homepage "https://github.com/SachsA/fidget"
  url "https://github.com/SachsA/fidget/releases/download/v__VERSION__/fidget-cli-__VERSION__.tar.gz"
  sha256 "__CLI_SHA__"
  license "MIT"

  depends_on macos: :ventura

  def install
    bin.install "fidget"
  end

  def caveats
    <<~EOS
      Fidget needs Accessibility access for the terminal app that runs it:
        System Settings > Privacy & Security > Accessibility
      For the menu bar app instead: brew install --cask sachsa/tap/fidget
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/fidget --version")
  end
end
