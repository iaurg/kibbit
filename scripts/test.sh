#!/bin/bash
# Runs the test suite. With only the Command Line Tools installed (no Xcode), Swift Testing
# lives outside the default search paths, so point the compiler and linker at it. The CLT also
# ship the Testing+Foundation cross-import overlay without its module, so that overlay is disabled.
set -euo pipefail
cd "$(dirname "$0")/.."

FLAGS=()
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    F="$(xcode-select -p)/Library/Developer/Frameworks"
    FLAGS=(-Xswiftc -F -Xswiftc "$F" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
           -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F")
fi
# `${FLAGS[@]+...}` because macOS bash 3.2 treats an empty array as unbound under `set -u`.
swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"
