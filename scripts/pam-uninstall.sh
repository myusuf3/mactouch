#!/bin/zsh
# Remove pam_mactouch from a PAM service (sudo by default).
#
#   sudo scripts/pam-uninstall.sh [--service su] [--purge]
#
# Drops the module line from /etc/pam.d/<service> and removes the module.
# The stored device key stays unless --purge is given, so a reinstall does
# not need another pairing touch.
set -euo pipefail

here="${0:A:h}"
service="sudo"
purge=false
while (( $# )); do
  case "$1" in
    --service) service="$2"; shift 2 ;;
    --purge) purge=true; shift ;;
    *) print -u2 "unknown option $1"; exit 2 ;;
  esac
done
(( EUID == 0 )) || { print -u2 "run with sudo"; exit 2 }

module_dst="/usr/local/lib/pam/pam_mactouch.so"
files=("/etc/pam.d/$service")
[[ "$service" == sudo ]] && files+=("/etc/pam.d/sudo_local")
for pam_file in $files; do
  if [[ -L "$pam_file" ]]; then
    grep -qF "$module_dst" "$pam_file" && print "$pam_file is a symlink; remove the pam_mactouch line through whatever manages it"
  elif [[ -f "$pam_file" ]] && grep -qF "$module_dst" "$pam_file"; then
    grep -vF "$module_dst" "$pam_file" > "$pam_file.tmp"
    install -m 444 -o root -g wheel "$pam_file.tmp" "$pam_file"
    rm -f "$pam_file.tmp"
    print "Removed pam_mactouch from $pam_file"
  fi
done

if grep -rqF "$module_dst" /etc/pam.d 2>/dev/null; then
  print "Other services still use the module; leaving $module_dst in place"
else
  rm -f "$module_dst"
  print "Removed $module_dst"
fi

if $purge; then
  rm -rf /etc/mactouch
  print "Removed /etc/mactouch and the stored device key"
fi
