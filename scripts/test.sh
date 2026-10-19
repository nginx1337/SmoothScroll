#!/bin/bash
# Runs unit tests. With Command Line Tools only (no Xcode) SwiftPM can't find
# the swift-testing macro plugin on its own, so point it there explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  exec swift test "$@"
fi
