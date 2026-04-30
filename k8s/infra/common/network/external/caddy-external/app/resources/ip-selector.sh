#!/bin/sh
set -eu

: "${MAIN_VPS_IP_V6:?MAIN_VPS_IP_V6 is required}"

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [ip-selector] $*"
}

update_ip() {
  # 优先读本机 eth1，避免外部探测服务失效影响 DDNS。
  # 备用探测命令：wget -6 -qO- https://ifconfig.co/ip
  # 备用探测命令：wget -6 -qO- https://6.icanhazip.com
  detected_ip="$(ip -6 addr show dev eth1 scope global 2>/dev/null | awk '$1 == "inet6" && $2 ~ /^2408:/ { sub(/\/.*/, "", $2); print $2; exit }')"

  if [ -n "$detected_ip" ]; then
    echo "$detected_ip" >/tmp/current-ip
    log "Using unicom IP: $detected_ip"
    return 0
  fi

  echo "$MAIN_VPS_IP_V6" >/tmp/current-ip
  log "Using VPS IP (local 2408 not found)"
}

for i in 1 2 3 4 5; do
  update_ip && break
  log "Retry $i/5..."
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
