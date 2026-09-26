#!/bin/bash
# Runs the Swift test suite. With only the Command Line Tools installed (no Xcode), SwiftPM does
# not add the swift-testing framework search/runtime paths, so pass them explicitly.
#
#   scripts/test.sh                         # unit tests
#   scripts/test.sh --filter VirtualDisplay # subset
#   T2M_INTEGRATION=1 scripts/test.sh       # also create a real virtual display (changes your display layout briefly)
set -euo pipefail
cd "$(dirname "$0")/.."

extra=()
developer_dir="$(xcode-select -p)"
if [[ "$developer_dir" == *CommandLineTools* ]]; then
    frameworks="$developer_dir/Library/Developer/Frameworks"
    libs="$developer_dir/Library/Developer/usr/lib"
    extra=(-Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$libs")
fi

exec swift test "${extra[@]}" "$@"
