#!/usr/bin/env bash
# Create a local code-signing identity for Diskwatch.app, so macOS privacy permissions
# (Full Disk Access) follow the certificate instead of one build's hash and survive rebuilds.
#
#   ./create-signing-cert.sh        run once, in your own terminal
#
# - Self-signed certificate "Diskwatch Local Code Signing" (10 years, code signing only).
# - Imported into the login keychain; only /usr/bin/codesign may use the private key.
# - Trusted for code signing (macOS asks for your password / Touch ID).
# - Temporary key files live in a private temp dir and are deleted on exit; nothing secret
#   is printed. build-app.sh uses this identity automatically when it exists.
set -euo pipefail
CN="Diskwatch Local Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$CN\""; then
  echo "Identity \"$CN\" already exists:"; security find-identity -v -p codesigning | grep "\"$CN\""
  exit 0
fi
command -v openssl >/dev/null || { echo "openssl not found (brew install openssl)"; exit 1; }

umask 077
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -subj "/CN=$CN" \
  -keyout "$work/signing-key" -out "$work/signing-cert" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

pass=$(openssl rand -hex 24)
openssl pkcs12 -export -in "$work/signing-cert" -inkey "$work/signing-key" -name "$CN" \
  -out "$work/identity.p12" -passout "pass:$pass" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import "$work/identity.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
unset pass
echo "Imported \"$CN\" into the login keychain (key usable by codesign only)."

echo "Trusting it for code signing — macOS will ask for your password or Touch ID…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$work/signing-cert"

echo; security find-identity -v -p codesigning | grep "\"$CN\"" \
  && echo "Done. Rebuild the app (./build-app.sh), then re-add it under Full Disk Access one last time."
