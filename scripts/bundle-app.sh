#!/bin/zsh
# Build MacTouch.app and install it in ~/Applications.
#
# There is no Xcode project: swift build makes the binary, this script lays
# out the bundle around it, signs it and copies it over. The product is
# MacTouchApp because Xcode's build engine folds product names case-
# insensitively and MacTouch would collide with the mactouch CLI; the
# binary is renamed MacTouch inside the bundle.
#
# Signing uses an "Apple Development" identity from the keychain when there
# is one, or the identity in MACTOUCH_SIGN_IDENTITY, and ad hoc otherwise. Re-run after
# changing the app; it quits a running copy first. Ad-hoc signing is enough
# on the Mac that built it; another Mac needs a Developer ID.
set -euo pipefail

here="${0:A:h}"
version="0.1.0"
stage="$here/../app/.build/MacTouch.app"
target="$HOME/Applications/MacTouch.app"

cd "$here/../app"
swift build -c release --product MacTouchApp 2>&1 | grep -E "error|Compiling|Build complete" | tail -3

rm -rf "$stage"
mkdir -p "$stage/Contents/MacOS"
install -m 755 .build/release/MacTouchApp "$stage/Contents/MacOS/MacTouch"
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
identity="${MACTOUCH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --sign "${identity:--}" "$stage" 2>&1 | grep -v 'replacing existing signature' || true
print "Signed as ${identity:-ad hoc}"

pkill -x MacTouch 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$target"
ditto "$stage" "$target"
print "Installed $target"
print "Run it: open $target"
