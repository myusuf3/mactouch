#!/bin/zsh
# Install mactouchd as a launch agent and put the mactouch CLI on PATH,
# without the app. This is the developer path for a checkout; with the app,
# scripts/bundle-app.sh installs everything and the app owns the agent.
#
# Builds release binaries, copies them to ~/.local/bin, writes the launchd
# plist to ~/Library/LaunchAgents and loads it. Re-run after changing the
# daemon; it replaces the binaries and restarts the agent.
set -euo pipefail

here="${0:A:h}"
label="dev.mactouch.daemon"
if [[ -d "$HOME/Applications/MacTouch.app" ]]; then
  print -u2 "MacTouch.app is installed and manages the daemon; run scripts/bundle-app.sh instead."
  exit 1
fi
bin="$HOME/.local/bin"
plist="$HOME/Library/LaunchAgents/$label.plist"
logs="$HOME/Library/Logs/mactouch"

cd "$here/../app"
swift build -c release 2>&1 | grep -E "error|Compiling|Build complete" | tail -3

mkdir -p "$bin" "$logs" "$HOME/Library/LaunchAgents"
launchctl bootout "gui/$UID/$label" 2>/dev/null || true
install -m 755 .build/release/mactouchd "$bin/mactouchd"
install -m 755 .build/release/mactouch "$bin/mactouch"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$bin/mactouchd</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$logs/mactouchd.log</string>
  <key>StandardErrorPath</key><string>$logs/mactouchd.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$UID" "$plist"
sleep 1
print "Installed. Daemon: $(launchctl print "gui/$UID/$label" 2>/dev/null | grep -E '^\s+state' | tr -d '\t')"
print "Log: $logs/mactouchd.log"
print "CLI: $bin/mactouch"
