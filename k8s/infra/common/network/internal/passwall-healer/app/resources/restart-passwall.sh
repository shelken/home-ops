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
	printf '%s\n' "$*" >&2
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

is_luci_exec_success() {
	printf '%s' "$1" | grep -Eq '"result"[[:space:]]*:[[:space:]]*(\[[[:space:]]*0[[:space:]]*\]|"0"|0|"")'
}

is_luci_error_null() {
	printf '%s' "$1" | grep -Eq '"error"[[:space:]]*:[[:space:]]*null'
}

log "received passwall-healer request method=${REQUEST_METHOD:-unknown}"
if [ "${REQUEST_METHOD:-}" != "POST" ]; then
	log "ignored passwall-healer request reason=method method=${REQUEST_METHOD:-unknown}"
	respond_ok "ignored: method ${REQUEST_METHOD:-unknown}"
	exit 0
fi

payload="$(cat)"
payload_bytes="$(printf '%s' "$payload" | wc -c | tr -d ' ')"
log "received passwall-healer payload bytes=${payload_bytes}"
if ! echo "$payload" | grep -q '"autoheal":"passwall-restart"'; then
	log "ignored passwall-healer request reason=unmatched-alert-payload"
	respond_ok "ignored: unmatched alert payload"
	exit 0
fi
log "matched passwall-healer payload autoheal=passwall-restart"

if [ -z "${ROUTER_HOST:-}" ] || [ -z "${AUTH_PASSWORD:-}" ]; then
	log "failed passwall-healer config reason=missing-router-host-or-auth-password"
	respond_err "failed: missing ROUTER_HOST or AUTH_PASSWORD"
	exit 1
fi

minimum_retrigger_interval_seconds=90
last_trigger_file="/tmp/passwall-restart.last"

lock_dir="/tmp/passwall-restart.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
	log "ignored passwall restart reason=already-running"
	respond_ok "ignored: passwall restart already running"
	exit 0
fi
trap 'rmdir "$lock_dir"' EXIT INT TERM

now_epoch="$(date +%s)"
if [ -f "$last_trigger_file" ]; then
	last_trigger_epoch="$(sed -n '1p' "$last_trigger_file")"
	case "$last_trigger_epoch" in
	'' | *[!0-9]*)
		last_trigger_epoch=''
		;;
	esac
	if [ -n "$last_trigger_epoch" ]; then
		elapsed_seconds=$((now_epoch - last_trigger_epoch))
		if [ "$elapsed_seconds" -le "$minimum_retrigger_interval_seconds" ]; then
			log "ignored passwall restart reason=cooldown elapsed_seconds=${elapsed_seconds} minimum_seconds=${minimum_retrigger_interval_seconds}"
			respond_ok "ignored: passwall restart cooldown ${elapsed_seconds}s <= ${minimum_retrigger_interval_seconds}s"
			exit 0
		fi
	fi
fi

rpc_base="http://${ROUTER_HOST}/cgi-bin/luci/rpc"
auth_password_escaped="$(json_escape "$AUTH_PASSWORD")"
login_payload="$(printf '{"id":1,"method":"login","params":["root","%s"]}' "$auth_password_escaped")"

log "requesting luci auth router_host=${ROUTER_HOST}"
if ! login_resp="$(
	wget -T 15 -qO- \
		--header 'Content-Type: application/json' \
		--post-data "$login_payload" \
		"${rpc_base}/auth"
)"; then
	log "failed luci auth reason=request-timeout router_host=${ROUTER_HOST}"
	respond_err "failed: luci auth request timeout"
	exit 1
fi

token="$(echo "$login_resp" | sed -n 's/.*"result"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -z "$token" ] || [ "$token" = "null" ]; then
	log "failed luci auth reason=token-missing router_host=${ROUTER_HOST}"
	respond_err "failed: luci auth token missing"
	exit 1
fi
log "luci auth ok router_host=${ROUTER_HOST}"

command_payload='{"id":1,"method":"exec","params":["sh -c '\''rm -f /tmp/lock/passwall_monitor.lock; /etc/init.d/passwall restart >/tmp/passwall-healer-restart.log 2>&1 </dev/null &'\''"]}'
log "requesting passwall restart router_host=${ROUTER_HOST}"
if ! exec_resp="$(
	wget -T 15 -qO- \
		--header 'Content-Type: application/json' \
		--post-data "$command_payload" \
		"${rpc_base}/sys?auth=${token}"
)"; then
	log "failed passwall restart reason=request-timeout router_host=${ROUTER_HOST}"
	respond_err "failed: passwall restart request timeout"
	exit 1
fi
log "luci exec response=${exec_resp}"

if ! is_luci_error_null "$exec_resp"; then
	log "failed luci exec reason=error-response response=${exec_resp}"
	respond_err "failed: luci exec error ${exec_resp}"
	exit 1
fi

if ! is_luci_exec_success "$exec_resp"; then
	log "failed luci exec reason=unexpected-result response=${exec_resp}"
	respond_err "failed: luci exec unexpected result ${exec_resp}"
	exit 1
fi

printf '%s\n' "$now_epoch" >"$last_trigger_file"

log "passwall restart requested router_host=${ROUTER_HOST}"
respond_ok "ok: passwall restart requested"
