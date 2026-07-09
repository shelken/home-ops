#!/bin/sh
set -e

CERT_DIR="/etc/sing-box/cert"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  mkdir -p "$CERT_DIR"
  umask 077
  tmp_pair=$(mktemp)
  /usr/local/bin/sing-box generate tls-keypair git.opslab.net -m 120 > "$tmp_pair"
  awk '/BEGIN PRIVATE KEY/{key=1} key{print} /END PRIVATE KEY/{key=0}' "$tmp_pair" > "$KEY_FILE"
  awk '/BEGIN CERTIFICATE/{cert=1} cert{print} /END CERTIFICATE/{cert=0}' "$tmp_pair" > "$CERT_FILE"
  test -s "$KEY_FILE"
  test -s "$CERT_FILE"
  rm -f "$tmp_pair"
fi

exec /usr/local/bin/sing-box run -c /etc/sing-box/config.json
