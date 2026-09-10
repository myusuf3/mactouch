#!/bin/zsh
# Start, stop or restart the installed mactouchd launch agent.
set -euo pipefail
label="dev.mactouch.daemon"
case "${1:-}" in
  stop)    launchctl bootout "gui/$UID/$label" 2>/dev/null || true ;;
  start)   launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/$label.plist" ;;
  restart) launchctl kickstart -k "gui/$UID/$label" ;;
  status)  launchctl print "gui/$UID/$label" 2>/dev/null | grep -E "state|pid" || print "not loaded" ;;
  *) print -u2 "usage: daemon.sh start|stop|restart|status"; exit 2 ;;
esac
