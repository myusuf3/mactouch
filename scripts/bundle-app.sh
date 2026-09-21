#!/bin/zsh
# Build MacTouch.app and install it in ~/Applications. This is the install
# path: the app carries mactouchd and the mactouch CLI, registers the daemon
# as its launch agent on launch, and the CLI is symlinked into ~/.local/bin.
#
# There is no Xcode project: swift build makes the binaries, this script lays
# out the bundle around them, signs it and copies it over. Re-run after
# changing anything; it quits a running copy, restarts the daemon and opens
# the app again. The product is MacTouchApp because Xcode's build engine
# folds product names case-insensitively and MacTouch would collide with the
# mactouch CLI; the binary is renamed MacTouch inside the bundle. The CLI
# lives in Contents/Helpers for the same reason: on a case-insensitive volume
# Contents/MacOS/mactouch is Contents/MacOS/MacTouch.
#
# Signing uses an "Apple Development" identity from the keychain when there
# is one, or the identity in MACTOUCH_SIGN_IDENTITY, and ad hoc otherwise.
set -euo pipefail

here="${0:A:h}"
version="0.1.0"
label="dev.mactouch.daemon"
stage="$here/../app/.build/MacTouch.app"
target="$HOME/Applications/MacTouch.app"
bin="$HOME/.local/bin"
logs="$HOME/Library/Logs/mactouch"

cd "$here/../app"
swift build -c release 2>&1 | grep -E "error|Compiling|Build complete" | tail -3

rm -rf "$stage"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Helpers" "$stage/Contents/Library/LaunchAgents" "$logs"
install -m 755 .build/release/MacTouchApp "$stage/Contents/MacOS/MacTouch"
install -m 755 .build/release/mactouchd "$stage/Contents/MacOS/mactouchd"
install -m 755 .build/release/mactouch "$stage/Contents/Helpers/mactouch"
cat > "$stage/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.mactouch.app</string>
  <key>CFBundleName</key><string>MacTouch</string>
  <key>CFBundleExecutable</key><string>MacTouch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# The daemon's launch agent, registered by the app through SMAppService.
# BundleProgram is relative to the bundle, so the agent follows the app when
# it moves. The log paths are this user's; the bundle is built per machine.
cat > "$stage/Contents/Library/LaunchAgents/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>BundleProgram</key><string>Contents/MacOS/mactouchd</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$logs/mactouchd.log</string>
  <key>StandardErrorPath</key><string>$logs/mactouchd.log</string>
</dict>
</plist>
PLIST
# The helpers are signed first and with the same identity: launchd refuses
# to spawn an SMAppService agent whose executable is not signed like the app
# that registered it (launchctl print shows OS_REASON_CODESIGNING).
identity="${MACTOUCH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
for helper in "$stage"/Contents/Helpers/* "$stage/Contents/MacOS/mactouchd"; do
  codesign --force --sign "${identity:--}" "$helper" 2>&1 | grep -v 'replacing existing signature' || true
done
codesign --force --sign "${identity:--}" "$stage" 2>&1 | grep -v 'replacing existing signature' || true
print "Signed as ${identity:-ad hoc}"

pkill -x MacTouch 2>/dev/null || true
mkdir -p "$HOME/Applications" "$bin"
rm -rf "$target"
ditto "$stage" "$target"
ln -sfn "$target/Contents/Helpers/mactouch" "$bin/mactouch"

# The app registers the agent when it opens, and SMAppService keeps the
# registration it has, so an agent it already knows is unloaded first: the
# app then registers this bundle's plist and binaries afresh. A stale
# mactouchd from install.sh goes once its plist is gone.
if launchctl print "gui/$UID/$label" 2>/dev/null | grep -q 'com.apple.xpc.ServiceManagement'; then
  launchctl bootout "gui/$UID/$label" 2>/dev/null || true
fi
if [[ ! -f "$HOME/Library/LaunchAgents/$label.plist" ]]; then
  rm -f "$bin/mactouchd"
fi
open "$target"
print "Installed $target"
print "CLI: $bin/mactouch -> $target/Contents/Helpers/mactouch"
print "Log: $logs/mactouchd.log"
