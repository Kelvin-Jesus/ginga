#!/bin/bash
# Everything a change must pass before it's done, and what CI runs: Swift tests, golden-vector
# freshness (the committed vectors must equal what the Mac generates), private-API containment,
# release build, Android tests + debug APK.
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
    (cd mac && swift build --product ginga >/dev/null)
    fresh="$(mktemp -d)"
    trap 'rm -rf "$fresh"' EXIT
    mac/.build/debug/ginga protocol-vectors --out "$fresh" >/dev/null
    diff -r "$fresh" protocol/test-vectors >/dev/null || { echo "protocol/test-vectors is stale: run mac/.build/debug/ginga protocol-vectors --out protocol/test-vectors" >&2; exit 1; }
    echo "== Private API stays in CGVirtualDisplayShim (invariant 5)"
    # Runtime lookups and the private classes only in the shim; dlopen/dlsym only for IOReport (EnergyMeter).
    leaks="$(grep -rnE 'NSClassFromString|objc_getClass|objc_msgSend|CGVirtualDisplay(Descriptor|Settings|Mode)\b' mac/Sources | grep -v '^mac/Sources/CGVirtualDisplayShim/' || true)"
    leaks+="$(grep -rnE '\b(dlopen|dlsym)\(' mac/Sources | grep -vE '^mac/Sources/(CGVirtualDisplayShim|EnergyMeter)/' || true)"
    [[ -z "$leaks" ]] || { echo "private API used outside CGVirtualDisplayShim:" >&2; echo "$leaks" >&2; exit 1; }
    echo "== Release build (as CI)"
    (cd mac && swift build -c release >/dev/null)
fi

if (( run_android )); then
    echo "== Android tests"
    java_home="${JAVA_HOME:-}"
    [[ -z "$java_home" && -d /opt/homebrew/opt/openjdk@17 ]] && java_home=/opt/homebrew/opt/openjdk@17
    (cd android && JAVA_HOME="$java_home" ./gradlew test assembleDebug --console=plain -q)
fi
echo "All checks passed."
