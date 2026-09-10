#!/bin/zsh
# Runs the Swift tests. The command line tools ship Swift Testing outside the
# toolchain's search path, so `swift test` needs to be told where it is.
set -euo pipefail
cd "${0:A:h}/../app"
frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
interop=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test \
  -Xswiftc -F"$frameworks" \
  -Xlinker -F"$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$interop" "$@"
