#!/bin/bash
# Checks (and with --install, sets up through Homebrew) what Tab2Mac development needs.
# Never changes system settings; never uses sudo.
set -uo pipefail
install=0; [[ "${1:-}" == "--install" ]] && install=1
missing=0
ok()   { printf "  ✓ %s\n" "$1"; }
miss() { printf "  ✗ %s — %s\n" "$1" "$2"; missing=$((missing + 1)); }

echo "Mac toolchain"
[[ "$(uname -s)" == "Darwin" ]] && ok "macOS $(sw_vers -productVersion)" || miss "macOS" "the Mac app needs macOS 14+ on Apple Silicon (Android parts build anywhere: scripts/docker-android.sh)"
[[ "$(uname -m)" == "arm64" ]] && ok "Apple Silicon" || miss "Apple Silicon" "Intel Macs are untested"
if command -v swift >/dev/null; then ok "$(swift --version 2>&1 | head -1)"; else miss "Swift 6" "xcode-select --install"; fi

echo "Android toolchain"
if command -v brew >/dev/null; then
    for formula in openjdk@17 android-platform-tools; do
        if brew list "$formula" >/dev/null 2>&1; then ok "$formula"
        elif (( install )); then brew install "$formula" && ok "$formula (installed)"
        else miss "$formula" "brew install $formula"; fi
    done
    sdk="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
    if [[ -d "$sdk/platforms" ]]; then ok "Android SDK at $sdk"
    elif (( install )); then brew install --cask android-commandlinetools && ok "Android SDK (installed; accept licences with sdkmanager --licenses)"
    else miss "Android SDK" "brew install --cask android-commandlinetools, then sdkmanager 'platforms;android-36' 'build-tools;36.0.0'"; fi
else
    miss "Homebrew" "https://brew.sh (or use scripts/docker-android.sh for Android)"
fi

echo "Optional"
command -v docker >/dev/null && ok "docker (for scripts/docker-android.sh; start OrbStack/Docker first)" || echo "  - docker not found (only needed for container builds)"
security find-identity -p codesigning 2>/dev/null | grep -q '"Tab2Mac Development"' && ok "Tab2Mac Development signing identity" \
    || echo "  - no 'Tab2Mac Development' identity: permissions reset on every rebuild (mac/scripts/create-dev-signing-identity.sh; read it first)"

(( missing == 0 )) && echo "Ready." || { echo "$missing missing."; exit 1; }
