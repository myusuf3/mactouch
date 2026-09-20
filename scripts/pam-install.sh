#!/bin/zsh
# Make a PAM service (sudo by default) accept a fingerprint.
#
#   sudo scripts/pam-install.sh [--service su] [--repair]
#
# Pairs with the device as the invoking user, stores the device key root-only
# in /etc/mactouch/<user>.key, installs pam_mactouch.so under
# /usr/local/lib/pam and adds an `auth sufficient` line at the top of
# /etc/pam.d/<service>. Everything short of a verified fingerprint falls
# through to the password, and the original service file is kept next to it.
#
# Pairing needs mactouchd running and a touch; the device releases its key
# once per boot, so a second attempt needs a replug. --repair pairs again
# even if a key is stored, which is how to rotate after a reflash.
set -euo pipefail

here="${0:A:h}"
service="sudo"
repair=false
while (( $# )); do
  case "$1" in
    --service) service="$2"; shift 2 ;;
    --repair) repair=true; shift ;;
    *) print -u2 "unknown option $1"; exit 2 ;;
  esac
done

(( EUID == 0 )) || { print -u2 "run with sudo"; exit 2 }
if [[ "$service" == screensaver || "$service" == authorization ]]; then
  print -u2 "$service runs inside loginwindow, a platform binary that loads only Apple-signed code;"
  print -u2 "the kernel rejects third-party PAM modules there. See docs/USAGE.md."
  exit 2
fi
user="${SUDO_USER:-}"
[[ -n "$user" && "$user" != root ]] || { print -u2 "run with sudo from your own account, not a root shell"; exit 2 }
home="$(dscl . -read "/Users/$user" NFSHomeDirectory | awk '{print $2}')"
[[ -d "$home" ]] || { print -u2 "no home directory for $user"; exit 2 }

module_src="$here/../pam"
module_dst="/usr/local/lib/pam/pam_mactouch.so"
key_dir="/etc/mactouch"
key_file="$key_dir/$user.key"
pam_file="/etc/pam.d/$service"
# Apple includes sudo_local from sudo so local additions survive OS updates;
# use it unless a config manager owns it (a symlink, as nix-darwin makes), in
# which case the line goes into sudo itself and an OS update may reset it.
# `mactouch doctor` names the services that carry the line.
if [[ "$service" == sudo && -f /etc/pam.d/sudo_local.template && ! -L /etc/pam.d/sudo_local ]]; then
  pam_file="/etc/pam.d/sudo_local"
  [[ -e "$pam_file" ]] || cp -p /etc/pam.d/sudo_local.template "$pam_file"
fi
backup="$pam_file.mactouch-backup"
line="auth       sufficient     $module_dst"
[[ -f "$pam_file" ]] || { print -u2 "$pam_file does not exist"; exit 2 }
[[ -L "$pam_file" ]] && { print -u2 "$pam_file is a symlink; edit it through whatever manages it"; exit 2 }

mactouch="$home/.local/bin/mactouch"
[[ -x "$mactouch" ]] || mactouch="$here/../app/.build/debug/mactouch"
[[ -x "$mactouch" ]] || { print -u2 "no mactouch binary; run scripts/install.sh or swift build first"; exit 2 }
[[ -S "$home/Library/Application Support/MacTouch/control.sock" ]] || { print -u2 "mactouchd is not running for $user; start it first"; exit 2 }

print "Building the module as $user"
# Xcode may be installed but unlicensed; the command line tools always build this.
[[ -d /Library/Developer/CommandLineTools ]] && export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
sudo -H -u "$user" env DEVELOPER_DIR="${DEVELOPER_DIR:-}" make -C "$module_src" all >/dev/null
mkdir -p "${module_dst:h}"
install -m 644 -o root -g wheel "$module_src/build/pam_mactouch.so" "$module_dst"
print "Installed $module_dst"

if [[ -f "$key_file" ]] && ! $repair; then
  print "Keeping the stored key at $key_file (use --repair to pair again)"
else
  print "Pairing: touch the sensor when the ring breathes white"
  key="$(sudo -H -u "$user" "$mactouch" pair --timeout 60 2>/dev/null | sed -n 's/^key=\([0-9a-f]\{64\}\)$/\1/p')" || true
  if [[ -z "$key" ]]; then
    print -u2 "Pairing failed. The device releases its key once per boot; replug it and run again."
    exit 1
  fi
  mkdir -p "$key_dir"
  chmod 700 "$key_dir"
  umask 077
  print -r -- "$key" > "$key_file"
  chown root:wheel "$key_file"
  chmod 600 "$key_file"
  unset key
  print "Stored the device key at $key_file (root only)"
fi

if grep -qF "$module_dst" "$pam_file"; then
  print "$pam_file already uses pam_mactouch"
else
  [[ -f "$backup" ]] || cp -p "$pam_file" "$backup"
  # Insert after the leading comment block so the module is consulted first.
  awk -v line="$line" 'BEGIN{done=0} !done && !/^#/ {print line; done=1} {print}' "$pam_file" > "$pam_file.tmp"
  install -m 444 -o root -g wheel "$pam_file.tmp" "$pam_file"
  rm -f "$pam_file.tmp"
  print "Added to $pam_file:"
  print "  $line"
fi

print
print "Done. Keep this terminal open and test from another one:"
case "$service" in
  sudo) print "  sudo -k && sudo true      # ring breathes white; touch, or wait and type the password" ;;
  *) print "  $service $user            # ring breathes white; touch, or wait and type the password" ;;
esac
print "Undo with: sudo $here/pam-uninstall.sh --service $service"
print "Emergency: sudo cp $backup $pam_file"
