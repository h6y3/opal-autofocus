class OpalAutofocus < Formula
  desc "Keep the Opal C1 webcam's autofocus enabled without Opal Composer"
  homepage "https://github.com/h6y3/opal-autofocus"
  url "https://github.com/h6y3/opal-autofocus/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "c55e3c75514d90b656dfe4f6cdef63c30240647ca2a422636c82a4e34c2c0a8e"
  license "MIT"
  head "https://github.com/h6y3/opal-autofocus.git", branch: "main"

  depends_on macos: :sonoma
  uses_from_macos "swift" => :build

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/opal-autofocus"
    (prefix/"launchd").install "packaging/com.opal-autofocus.agent.plist"
  end

  service do
    run [opt_bin/"opal-autofocus", "watch"]
    keep_alive true
    log_path var/"log/opal-autofocus.log"
    error_log_path var/"log/opal-autofocus.log"
  end

  def caveats
    <<~EOS
      Start the resident watcher with:
        brew services start opal-autofocus

      To run nothing while the camera is unplugged, install the event-driven
      agent instead (launchd starts it on attach and it exits right away):
        mkdir -p ~/Library/Logs/opal-autofocus
        sed -e "s|@BIN@|#{opt_bin}/opal-autofocus|g" -e "s|@HOME@|$HOME|g" \\
          #{opt_prefix}/launchd/com.opal-autofocus.agent.plist \\
          > ~/Library/LaunchAgents/com.opal-autofocus.agent.plist
        launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.opal-autofocus.agent.plist

      Use one of the two, not both.
    EOS
  end

  test do
    assert_match "opal-autofocus", shell_output("#{bin}/opal-autofocus --help")
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/opal-autofocus --version"))
  end
end
