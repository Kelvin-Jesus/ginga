#!/bin/bash
# Creates a self-signed code-signing identity ("Ginga Development") in your login keychain.
#
# Why: macOS records privacy permissions (Screen Recording, later Post Event / Local Network)
# against the app's designated code requirement. Ad-hoc signatures are tied to one exact build,
# so every rebuild loses the permission. A stable certificate keeps it across rebuilds.
#
# This modifies your login keychain — read it before running. Remove the identity later with
# Keychain Access (search "Ginga Development") or `security delete-identity -c "Ginga Development"`.
set -euo pipefail
name="${1:-Ginga Development}"

if security find-identity -p codesigning | grep -q "\"$name\""; then
    echo "identity '$name' already exists"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/openssl.cnf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $name
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$tmp/openssl.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
password="$(uuidgen)"
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
    -out "$tmp/identity.p12" -passout "pass:$password"
security import "$tmp/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$password" -T /usr/bin/codesign
echo "created '$name' — scripts/build-app.sh will sign with it from now on"
