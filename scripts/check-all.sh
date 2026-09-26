#!/bin/bash
# Everything a change must pass before it's done: Swift tests, golden-vector freshness (the
# committed vectors must equal what the Mac generates), Android tests.
#
#   scripts/check-all.sh            # all
#   scripts/check-all.sh --mac      # Swift + vectors only
#   scripts/check-all.sh --android  # Android only
set -euo pipefail
cd "$(dirname "$0")/.."
run_mac=1; run_android=1
[[ "${1:-}" == "--mac" ]] && run_android=0
[[ "${1:-}" == "--android" ]] && run_mac=0

if (( run_mac )); then
    echo "== Swift tests"
    (cd mac && scripts/test.sh)
    echo "== Golden vectors are up to date"
    (cd mac && swift build --product t2m >/dev/null)
    fresh="$(mktemp -d)"
    trap 'rm -rf "$fresh"' EXIT
    mac/.build/debug/t2m protocol-vectors --out "$fresh" >/dev/null
    diff -r "$fresh" protocol/test-vectors >/dev/null || { echo "protocol/test-vectors is stale: run mac/.build/debug/t2m protocol-vectors --out protocol/test-vectors" >&2; exit 1; }
fi

if (( run_android )); then
    echo "== Android tests"
    java_home="${JAVA_HOME:-}"
    [[ -z "$java_home" && -d /opt/homebrew/opt/openjdk@17 ]] && java_home=/opt/homebrew/opt/openjdk@17
    (cd android && JAVA_HOME="$java_home" ./gradlew test --console=plain -q)
fi
echo "All checks passed."
