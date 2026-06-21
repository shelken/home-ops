#!/bin/sh
set -e

CERT_DIR="/etc/sing-box/cert"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  mkdir -p "$CERT_DIR"
  apk add --no-cache openssl > /dev/null 2>&1
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -nodes \
    -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/CN=git.opslab.net" \
    -addext "subjectAltName=DNS:git.opslab.net"
fi

exec /usr/local/bin/sing-box run -c /etc/sing-box/config.json
