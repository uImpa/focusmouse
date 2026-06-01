#!/bin/sh
set -eu

CERT_NAME="focusmouse-cert"
TMP_DIR="${TMPDIR:-/tmp}/focusmouse-cert"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
P12_PASSWORD="focusmouse"

if security find-identity -v -p codesigning | grep -q "\"$CERT_NAME\""; then
  echo "Code signing identity already exists: $CERT_NAME"
  exit 0
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/openssl.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[ req_distinguished_name ]
CN = $CERT_NAME

[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -new \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -keyout "$TMP_DIR/$CERT_NAME.key" \
  -out "$TMP_DIR/$CERT_NAME.crt" \
  -config "$TMP_DIR/openssl.cnf"

openssl pkcs12 \
  -export \
  -legacy \
  -passout pass:"$P12_PASSWORD" \
  -name "$CERT_NAME" \
  -inkey "$TMP_DIR/$CERT_NAME.key" \
  -in "$TMP_DIR/$CERT_NAME.crt" \
  -out "$TMP_DIR/$CERT_NAME.p12"

security import "$TMP_DIR/$CERT_NAME.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "" \
  "$KEYCHAIN" >/dev/null 2>&1 || true

rm -rf "$TMP_DIR"

echo "Created code signing identity: $CERT_NAME"
