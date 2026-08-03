#!/bin/bash
# One-time: create a stable self-signed code-signing identity so macOS keeps the
# Screen Recording permission across rebuilds (ad-hoc signatures change every
# build and reset the permission).
set -euo pipefail

NAME="ShotEditor Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "✓ Signing identity already exists: $NAME"
    exit 0
fi

TMP="$(mktemp -d)"
cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "▸ Generating self-signed code-signing certificate…"
openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" >/dev/null 2>&1

echo "▸ Importing certificate and key into the login keychain…"
# Import cert and key separately as PEM (avoids openssl-3 PKCS12 incompatibility).
security import "$TMP/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign -A >/dev/null 2>&1 || true
security import "$TMP/key.pem"  -k "$KEYCHAIN" -T /usr/bin/codesign -A >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

rm -rf "$TMP"
echo "✓ Created signing identity: $NAME"
echo "  Now run ./build.sh — it will sign with this identity."
echo "  Grant Screen Recording once; it will persist across rebuilds."
