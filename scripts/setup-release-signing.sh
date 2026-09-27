#!/bin/bash
# Creates the two release signing keys once and stores them as GitHub Actions secrets for
# .github/workflows/release.yml. Run it yourself: it asks for a password and never prints it.
#
#   scripts/setup-release-signing.sh                 # keys in ~/Ginga-release-keys, secrets on the repo's GitHub remote
#   GINGA_KEYS_DIR=/Volumes/Backup/ginga scripts/setup-release-signing.sh
#
# What it makes:
#   ginga-release.jks       Android upload key (alias "ginga"). Every future APK must be signed with
#                           it: lose it and people have to uninstall Ginga to update.
#   ginga-release.p12       Self-signed "Ginga Release" code-signing identity for the Mac app. Not
#                           trusted by Gatekeeper (that needs Apple's Developer ID), but a stable
#                           certificate makes macOS keep Screen Recording/Accessibility grants
#                           across updates, which ad-hoc signing does not.
# Both are protected by the password you type. Back up the folder and the password (a password
# manager); neither is recoverable.
#
# Secrets set: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, MAC_SIGNING_P12_BASE64,
# MAC_SIGNING_P12_PASSWORD. Needs `gh auth login` and a GitHub remote; without them it only
# creates the files and tells you what to set.
set -euo pipefail
cd "$(dirname "$0")/.."

dir="${GINGA_KEYS_DIR:-$HOME/Ginga-release-keys}"
keytool="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}/bin/keytool"
[[ -x "$keytool" ]] || { echo "keytool not found at $keytool (set JAVA_HOME to a JDK 17)" >&2; exit 1; }

mkdir -p "$dir"
chmod 700 "$dir"
jks="$dir/ginga-release.jks"
p12="$dir/ginga-release.p12"
if [[ -e "$jks" || -e "$p12" ]]; then
    echo "$dir already has release keys; refusing to replace them (an APK signed with a new key cannot update the old one)" >&2
    exit 1
fi

read -r -s -p "Password for the release keys (12+ characters): " password; echo
read -r -s -p "Again: " again; echo
[[ "$password" == "$again" ]] || { echo "passwords differ" >&2; exit 1; }
(( ${#password} >= 12 )) || { echo "too short" >&2; exit 1; }
export GINGA_RELEASE_PASSWORD="$password"

# Android: one key, 30 years (Play and sideloading both need the same key for every update).
"$keytool" -genkeypair -keystore "$jks" -storetype PKCS12 -alias ginga \
    -keyalg RSA -keysize 4096 -validity 10950 -dname "CN=Ginga" \
    -storepass:env GINGA_RELEASE_PASSWORD -keypass:env GINGA_RELEASE_PASSWORD >/dev/null

# Mac: self-signed code-signing certificate, same shape as mac/scripts/create-dev-signing-identity.sh.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/openssl.cnf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Ginga Release
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 10950 -nodes \
    -config "$tmp/openssl.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
# /usr/bin/openssl is LibreSSL: its PKCS#12 algorithms are the ones `security import` reads
# (OpenSSL 3 would need -legacy).
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "Ginga Release" \
    -out "$p12" -passout env:GINGA_RELEASE_PASSWORD
chmod 600 "$jks" "$p12"
echo "created $jks and $p12 — back up $dir and the password now"

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
    base64 < "$jks" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64
    printf '%s' "$password" | gh secret set ANDROID_KEYSTORE_PASSWORD
    base64 < "$p12" | tr -d '\n' | gh secret set MAC_SIGNING_P12_BASE64
    printf '%s' "$password" | gh secret set MAC_SIGNING_P12_PASSWORD
    echo "secrets set on $(gh repo view --json nameWithOwner -q .nameWithOwner)"
else
    echo "no GitHub remote or gh login yet: after 'gh auth login' and adding the remote, run from the repo:"
    echo "  base64 < $jks | tr -d '\\n' | gh secret set ANDROID_KEYSTORE_BASE64"
    echo "  gh secret set ANDROID_KEYSTORE_PASSWORD      # paste the password"
    echo "  base64 < $p12 | tr -d '\\n' | gh secret set MAC_SIGNING_P12_BASE64"
    echo "  gh secret set MAC_SIGNING_P12_PASSWORD       # paste the password"
fi
