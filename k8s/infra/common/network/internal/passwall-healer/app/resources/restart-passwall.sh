#!/bin/sh
set -eu

respond_ok() {
	printf 'Status: 200 OK\r\n'
	printf 'Content-Type: text/plain; charset=utf-8\r\n\r\n'
	printf '%s\n' "$1"
}

respond_err() {
	printf 'Status: 500 Internal Server Error\r\n'
	printf 'Content-Type: text/plain; charset=utf-8\r\n\r\n'
	printf '%s\n' "$1"
}

log() {
	ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
	printf '%s %s\n' "$ts" "$*" >&2
}

json_escape() {
	printf '%s' "$1" | awk '
		BEGIN { ORS = "" }
		{
			if (NR > 1) {
				printf "\\n"
			}
			for (i = 1; i <= length($0); i++) {
				c = substr($0, i, 1)
				if (c == "\\") {
					printf "\\\\"
				} else if (c == "\"") {
					printf "\\\""
				} else if (c == "\t") {
					printf "\\t"
				} else {
					printf "%s", c
				}
			}
		}
	'
}

has_null_error() {
	printf '%s' "$1" | grep -Eq '"error"[[:space:]]*:[[:space:]]*null'
}

log "received request method=${REQUEST_METHOD:-unknown}"
if [ "${REQUEST_METHOD:-}" != "POST" ]; then
	log "ignored request reason=method method=${REQUEST_METHOD:-unknown}"
	respond_ok "ignored: method ${REQUEST_METHOD:-unknown}"
	exit 0
fi

payload="$(cat)"
log "received payload"
if ! printf '%s' "$payload" | grep -q '"autoheal":"passwall-restart"'; then
	log "ignored request reason=unmatched-alert-payload"
	respond_ok "ignored: unmatched alert payload"
	exit 0
fi
log "matched payload autoheal=passwall-restart"

if [ -z "${ROUTER_HOST:-}" ] || [ -z "${AUTH_PASSWORD:-}" ]; then
	log "failed config reason=missing-router-host-or-auth-password"
	respond_err "failed: missing ROUTER_HOST or AUTH_PASSWORD"
	exit 1
fi

rpc_base="http://${ROUTER_HOST}/cgi-bin/luci/rpc"
auth_password_escaped="$(json_escape "$AUTH_PASSWORD")"
login_payload="$(printf '{"id":1,"method":"login","params":["root","%s"]}' "$auth_password_escaped")"

log "requesting luci auth router_host=${ROUTER_HOST}"
if ! login_resp="$(
	wget -T 10 -qO- \
		--header 'Content-Type: application/json' \
		--post-data "$login_payload" \
		"${rpc_base}/auth"
)"; then
	log "failed luci auth reason=request-timeout router_host=${ROUTER_HOST}"
	respond_err "failed: luci auth request timeout"
	exit 1
fi

token="$(printf '%s' "$login_resp" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -z "$token" ] || [ "$token" = "null" ]; then
	log "failed luci auth reason=token-missing router_host=${ROUTER_HOST}"
	respond_err "failed: luci auth token missing"
	exit 1
fi
log "luci auth ok router_host=${ROUTER_HOST}"

result_marker_recovered='__PASSWALL_DNS_RECOVERED__'
result_marker_singbox_missing='__SING_BOX_CMD_MISSING__'
result_marker_chinadns_missing='__CHINADNS_CMD_MISSING__'
result_marker_singbox_failed='__SING_BOX_START_FAILED__'
result_marker_chinadns_failed='__CHINADNS_START_FAILED__'
result_marker_singbox_port_failed='__SING_BOX_PORT_15353_MISSING__'
result_marker_chinadns_port_failed='__CHINADNS_PORT_15355_MISSING__'
result_marker_dns_failed='__ROUTER_DNS_PROXY_QUERY_FAILED__'

# 禁止只重启 chinadns-ng。why: 代理 DNS 链路依赖 sing-box 提供 127.0.0.1:15353，上游缺失时 chinadns-ng 活着也会超时。
# 禁止用“进程存在”作为成功标准。why: 必须验证 15353、15355 和 openai.com 解析都恢复。
# 保持显式失败，不做兜底。why: Passwall 运行态不完整时要暴露缺失组件，而不是假装恢复成功。
remote_script="$(cat <<EOF
singbox_cmd="\$(grep -h "sing-box run" /tmp/etc/passwall/script_func/* 2>/dev/null | head -n1)"
if [ -z "\$singbox_cmd" ]; then
  echo ${result_marker_singbox_missing}
  exit 1
fi

chinadns_cmd="\$(grep -h "chinadns-ng" /tmp/etc/passwall/script_func/* 2>/dev/null | head -n1)"
if [ -z "\$chinadns_cmd" ]; then
  echo ${result_marker_chinadns_missing}
  exit 1
fi

pidof sing-box >/dev/null 2>&1 && kill -9 \$(pidof sing-box) >/dev/null 2>&1
pidof chinadns-ng >/dev/null 2>&1 && kill -9 \$(pidof chinadns-ng) >/dev/null 2>&1
sleep 1

sh -c "\$singbox_cmd" >/dev/null 2>&1 </dev/null &
sleep 2
if ! pidof sing-box >/dev/null 2>&1; then
  echo ${result_marker_singbox_failed}
  exit 1
fi
if ! netstat -lntup 2>/dev/null | grep -q "127\.0\.0\.1:15353"; then
  echo ${result_marker_singbox_port_failed}
  exit 1
fi

sh -c "\$chinadns_cmd" >/dev/null 2>&1 </dev/null &
sleep 2
if ! pidof chinadns-ng >/dev/null 2>&1; then
  echo ${result_marker_chinadns_failed}
  exit 1
fi
if ! netstat -lntup 2>/dev/null | grep -q ":15355"; then
  echo ${result_marker_chinadns_port_failed}
  exit 1
fi

if ! nslookup openai.com 127.0.0.1 2>&1 | grep -q "Name:.*openai.com"; then
  echo ${result_marker_dns_failed}
  exit 1
fi

echo ${result_marker_recovered}
EOF
)"
remote_command="sh -c '$remote_script'"
command_payload="$(printf '{"id":1,"method":"exec","params":["%s"]}' "$(json_escape "$remote_command")")"

log "requesting passwall dns recovery router_host=${ROUTER_HOST}"
if ! exec_resp="$(
	wget -T 15 -qO- \
		--header 'Content-Type: application/json' \
		--post-data "$command_payload" \
		"${rpc_base}/sys?auth=${token}"
)"; then
	log "failed passwall dns recovery reason=request-timeout router_host=${ROUTER_HOST}"
	respond_err "failed: passwall dns recovery request timeout"
	exit 1
fi
log "luci exec response=${exec_resp}"

if ! has_null_error "$exec_resp"; then
	log "failed luci exec reason=error-response response=${exec_resp}"
	respond_err "failed: luci exec error ${exec_resp}"
	exit 1
fi

for marker in \
	"$result_marker_singbox_missing" \
	"$result_marker_chinadns_missing" \
	"$result_marker_singbox_failed" \
	"$result_marker_chinadns_failed" \
	"$result_marker_singbox_port_failed" \
	"$result_marker_chinadns_port_failed" \
	"$result_marker_dns_failed"; do
	if printf '%s' "$exec_resp" | grep -q "$marker"; then
		log "failed passwall dns recovery reason=${marker} router_host=${ROUTER_HOST}"
		respond_err "failed: passwall dns recovery ${marker}"
		exit 1
	fi
done

if ! printf '%s' "$exec_resp" | grep -q "$result_marker_recovered"; then
	log "failed passwall dns recovery reason=missing-result-marker response=${exec_resp}"
	respond_err "failed: passwall dns recovery result marker missing"
	exit 1
fi

log "passwall dns recovery ok router_host=${ROUTER_HOST}"
respond_ok "ok: passwall dns recovered"
