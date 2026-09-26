#!/bin/zsh
# Build the firmware and install it over the link, ADR-0018. No BOOT button:
# the board asks for a touch, writes its spare slot and restarts into it.
# Needs a board already on the two-slot layout; flash.sh is the way there.
#
#   scripts/update.sh            build and install
#   scripts/update.sh IMAGE      install a given image
set -euo pipefail
here="${0:A:h}"
image="${1:-}"
if [[ -z "$image" ]]; then
  eval "$(idf-env 2>/dev/null)" 2>/dev/null || true
  (cd "$here/../firmware" && idf.py build 2>&1 | grep -E "error|Project build complete" | tail -2)
  image="$here/../firmware/build/mactouch.bin"
fi
mactouch firmware update "$image"
