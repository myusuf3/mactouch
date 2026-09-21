#!/bin/zsh
# Start, stop or restart the mactouchd launch agent, whether install.sh wrote
# it or MacTouch.app registered it. The app re-registers its agent on every
# launch, so starting the bundled one means opening the app.
set -euo pipefail
label="dev.mactouch.daemon"
plist="$HOME/Library/LaunchAgents/$label.plist"
app="$HOME/Applications/MacTouch.app"
case "${1:-}" in
  stop)    launchctl bootout "gui/$UID/$label" 2>/dev/null || true ;;
  start)
    if [[ -f "$plist" ]]; then launchctl bootstrap "gui/$UID" "$plist"
    elif [[ -d "$app" ]]; then open -g "$app"
    else print -u2 "no launch agent; run scripts/bundle-app.sh or scripts/install.sh"; exit 1
    fi ;;
  restart) launchctl kickstart -k "gui/$UID/$label" ;;
  status)  launchctl print "gui/$UID/$label" 2>/dev/null | grep -E "state|pid" || print "not loaded" ;;
  *) print -u2 "usage: daemon.sh start|stop|restart|status"; exit 2 ;;
esac
