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

result_marker_restarted='__CHINADNS_RESTARTED__'
result_marker_not_running='__CHINADNS_NOT_RUNNING__'
result_marker_cmd_missing='__CHINADNS_CMD_MISSING__'
result_marker_failed='__CHINADNS_RESTART_FAILED__'

# 禁止把多行 shell 直接改写成分号串。why: if/then 结构很容易失真，路由器侧会只回 result=""。
# 禁止让重启后的子进程继承 rpc/sys.exec 的 stdout/stderr。why: rpc 会一直等待，调用方只会看到超时。
# 禁止只看 error=null 就判定成功。why: chinadns-ng 可能根本没起来，必须校验 PID 已变化。
# 这里保留多行脚本，便于阅读；启动 chinadns-ng 时断开 stdin/stdout/stderr；最后校验 PID 已变化。
remote_script="$(cat <<EOF
pid="\$(pidof chinadns-ng || true)"
if [ -z "\$pid" ]; then
  echo ${result_marker_not_running}
  exit 0
fi

cmd="\$(grep -h chinadns-ng /tmp/etc/passwall/script_func/* 2>/dev/null | head -n1 || true)"
if [ -z "\$cmd" ]; then
  echo ${result_marker_cmd_missing}
  exit 0
fi

set -- \$pid
old_pid="\${1:-}"
kill -9 \$pid >/dev/null 2>&1
sleep 1
sh -c "\$cmd" >/dev/null 2>&1 </dev/null &
sleep 1

new_pid="\$(pidof chinadns-ng || true)"
set -- \$new_pid
new_pid="\${1:-}"
if [ -n "\$new_pid" ] && [ "\$new_pid" != "\$old_pid" ]; then
  echo ${result_marker_restarted}
else
  echo ${result_marker_failed}
fi
EOF
)"
remote_command="sh -c '$remote_script'"
command_payload="$(printf '{"id":1,"method":"exec","params":["%s"]}' "$(json_escape "$remote_command")")"

log "requesting chinadns restart router_host=${ROUTER_HOST}"
if ! exec_resp="$(
	wget -T 10 -qO- \
		--header 'Content-Type: application/json' \
		--post-data "$command_payload" \
		"${rpc_base}/sys?auth=${token}"
)"; then
	log "failed chinadns restart reason=request-timeout router_host=${ROUTER_HOST}"
	respond_err "failed: chinadns restart request timeout"
	exit 1
fi
log "luci exec response=${exec_resp}"

if ! has_null_error "$exec_resp"; then
	log "failed luci exec reason=error-response response=${exec_resp}"
	respond_err "failed: luci exec error ${exec_resp}"
	exit 1
fi

if printf '%s' "$exec_resp" | grep -q "$result_marker_not_running"; then
	log "ignored chinadns restart reason=chinadns-not-running router_host=${ROUTER_HOST}"
	respond_ok "ignored: chinadns-ng not running"
	exit 0
fi

if printf '%s' "$exec_resp" | grep -q "$result_marker_cmd_missing"; then
	log "failed chinadns restart reason=startup-command-missing router_host=${ROUTER_HOST}"
	respond_err "failed: chinadns startup command missing"
	exit 1
fi

if printf '%s' "$exec_resp" | grep -q "$result_marker_failed"; then
	log "failed chinadns restart reason=pid-unchanged-or-process-missing router_host=${ROUTER_HOST}"
	respond_err "failed: chinadns restart verification failed"
	exit 1
fi

if ! printf '%s' "$exec_resp" | grep -q "$result_marker_restarted"; then
	log "failed chinadns restart reason=missing-result-marker response=${exec_resp}"
	respond_err "failed: chinadns restart result marker missing"
	exit 1
fi

log "chinadns restart ok router_host=${ROUTER_HOST}"
respond_ok "ok: chinadns restart requested"
