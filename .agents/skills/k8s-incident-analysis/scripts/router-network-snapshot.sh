#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  router-network-snapshot.sh <ROUTER_HOST>

可选环境变量:
  WWAN_IF=phy0-sta0
  WAN_IF=wan
  WWAN_GW=<wwan 上游网关>
  WAN_GW=<wan 上游网关>
  TEST_IP=223.5.5.5
  PROXY_DOMAIN=openai.com
  DIRECT_DOMAIN=qq.com
  UPSTREAM_DNS=<额外想测的上游 DNS>
EOF
}

ROUTER_HOST="${1:-${ROUTER_HOST:-}}"
if [[ -z "${ROUTER_HOST}" ]]; then
  usage >&2
  exit 1
fi

WWAN_IF="${WWAN_IF:-phy0-sta0}"
WAN_IF="${WAN_IF:-wan}"
WWAN_GW="${WWAN_GW:-}"
WAN_GW="${WAN_GW:-}"
TEST_IP="${TEST_IP:-223.5.5.5}"
PROXY_DOMAIN="${PROXY_DOMAIN:-openai.com}"
DIRECT_DOMAIN="${DIRECT_DOMAIN:-qq.com}"
UPSTREAM_DNS="${UPSTREAM_DNS:-}"

ssh -o BatchMode=yes -o ConnectTimeout=5 "${ROUTER_HOST}" 'sh -s' -- \
  "${WWAN_IF}" "${WAN_IF}" "${WWAN_GW}" "${WAN_GW}" "${TEST_IP}" "${PROXY_DOMAIN}" "${DIRECT_DOMAIN}" "${UPSTREAM_DNS}" <<'EOF'
set -eu

WWAN_IF="$1"
WAN_IF="$2"
WWAN_GW="$3"
WAN_GW="$4"
TEST_IP="$5"
PROXY_DOMAIN="$6"
DIRECT_DOMAIN="$7"
UPSTREAM_DNS="$8"

section() {
  printf '\n=== %s ===\n' "$1"
}

measure_dns() {
  local name="$1"
  local server="$2"
  local count="${3:-4}"
  local i=1
  while [ "$i" -le "$count" ]; do
    read s _ </proc/uptime
    if out="$(nslookup "$name" "$server" 2>&1)"; then
      rc=0
    else
      rc=$?
    fi
    read e _ </proc/uptime
    elapsed=$(awk -v s="$s" -v e="$e" 'BEGIN{printf "%.3f", e-s}')
    sample=$(printf '%s\n' "$out" | grep -m1 -E '^Name:|^Address:' || true)
    printf 'query=%s server=%s run=%s rc=%s elapsed=%ss sample=%s\n' "$name" "$server" "$i" "$rc" "$elapsed" "$sample"
    i=$((i + 1))
  done
}

section identity
printf 'date=%s\n' "$(date -Iseconds)"
printf 'hostname=%s\n' "$(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"

section routes
ip route show default || true
ip rule show || true

section interfaces
ubus call network.interface dump || true

section resources
uptime || true
free || true
printf 'nf_conntrack_count='; cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || true
printf 'nf_conntrack_max='; cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || true

section wireless_overview
iw dev || true
iwinfo 2>/dev/null || true

section wwan_link
iw dev "$WWAN_IF" link 2>/dev/null || true
iw dev "$WWAN_IF" station dump 2>/dev/null || true

section passwall_ports
pidof sing-box 2>/dev/null || true
pidof chinadns-ng 2>/dev/null || true
netstat -lntup 2>/dev/null | grep -E '127\.0\.0\.1:15353|:15355|:53 ' || true

if [ -n "$WWAN_GW" ]; then
  section ping_wwan_gateway
  ping -c 10 -W 1 -I "$WWAN_IF" "$WWAN_GW" || true
fi

if [ -n "$WAN_GW" ]; then
  section ping_wan_gateway
  ping -c 10 -W 1 -I "$WAN_IF" "$WAN_GW" || true
fi

section route_to_test_ip
ip route get "$TEST_IP" || true

section ping_test_ip_via_wwan
ping -c 10 -W 2 -I "$WWAN_IF" "$TEST_IP" || true

section ping_test_ip_via_wan
ping -c 10 -W 2 -I "$WAN_IF" "$TEST_IP" || true

section dns_local_proxy
measure_dns "$PROXY_DOMAIN" 127.0.0.1 4
measure_dns "$DIRECT_DOMAIN" 127.0.0.1 4

if [ -n "$UPSTREAM_DNS" ]; then
  section dns_custom_upstream
  measure_dns "$PROXY_DOMAIN" "$UPSTREAM_DNS" 4
  measure_dns "$DIRECT_DOMAIN" "$UPSTREAM_DNS" 4
fi

if [ -n "$WWAN_GW" ]; then
  section dns_wwan_gateway
  measure_dns "$PROXY_DOMAIN" "$WWAN_GW" 4
  measure_dns "$DIRECT_DOMAIN" "$WWAN_GW" 4
fi

if [ -n "$WAN_GW" ]; then
  section dns_wan_gateway
  measure_dns "$PROXY_DOMAIN" "$WAN_GW" 4
  measure_dns "$DIRECT_DOMAIN" "$WAN_GW" 4
fi

section recent_wireless_log
logread | grep -Ei 'phy0-sta0|phy1-sta0|wpa_supplicant|BEACON-LOSS|deauth|disassoc|disconnect|network.interface.wwan' | tail -n 120 || true

section recent_passwall_log
logread | grep -Ei 'passwall|sing-box|chinadns-ng|dnsmasq' | tail -n 120 || true
EOF
