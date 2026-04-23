#!/bin/sh
set -eu

: "${MAIN_VPS_IP_V6:?MAIN_VPS_IP_V6 is required}"

update_ip() {
  detected_ip="$(wget -qO- https://6.ipw.cn 2>/dev/null || true)"

  if [ -z "$detected_ip" ]; then
    echo "[ip-selector] Failed to detect IP, keeping previous"
    return 1
  fi

  case "$detected_ip" in
    2408:*)
      echo "$detected_ip" >/tmp/current-ip
      echo "[ip-selector] Using unicom IP: $detected_ip"
      ;;
    *)
      echo "$MAIN_VPS_IP_V6" >/tmp/current-ip
      echo "[ip-selector] Using VPS IP (non-2408 detected: $detected_ip)"
      ;;
  esac
}

for i in 1 2 3 4 5; do
  update_ip && break
  echo "[ip-selector] Retry $i/5..."
  sleep 5
done

while true; do
  sleep 270
  update_ip || true
done &

while true; do
  {
    printf 'HTTP/1.1 200 OK\r\n\r\n%s\n' "$(cat /tmp/current-ip 2>/dev/null)"
  } | nc -l -p 8888 >/dev/null
done
