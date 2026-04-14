#!/bin/sh
set -eu
# 部署脚本统一放在 zte-mifi-healer 模块，避免与 exporter 产生双份漂移。
# CGI 过滤交给专用 wrapper，主脚本只保留 CLI 能力。
# +login+ -> +disconnect+ -> +connect+ -> +verify realtime_time+
# AD 关键事实（MU5120 实测）：
# 1) CONNECT/DISCONNECT 属于受保护 POST，请求必须带 AD。
# 2) AD 不是长效值。复用旧 AD 时，设备常返回 HTTP 200 + 空响应。
# 3) Web UI 每次 POST 前都会重新取 RD 并重算 AD。
# 4) CLI 需要与 Web UI 同步：每次 POST 前刷新 AD。

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >&2; }
die() {
    log "failed: $*"
    exit 1
}
field() { printf '%s' "$2" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\{0,1\\}\\([^\",}]*\\)\"\\{0,1\\}.*/\\1/p"; }
sha_u() { printf %s "$1" | sha256sum | awk '{print toupper($1)}'; }
ok() { printf '%s' "$1" | grep -Eq '"result"[[:space:]]*:[[:space:]]*("success"|"?0"?)'; }
connected() {
    case "${1:-}" in ipv4_ipv6_connected | ipv4_connected | ipv6_connected) return 0 ;; esac
    return 1
}
has_cmd() { command -v "$1" >/dev/null 2>&1; }
fmt_dur() {
    v="$1"
    case "$v" in '' | *[!0-9]*)
        printf 'unknown'
        return
        ;;
    esac
    h=$((v / 3600))
    m=$(((v % 3600) / 60))
    s=$((v % 60))
    printf '%02d:%02d:%02d' "$h" "$m" "$s"
}
fmt_rate() {
    v="$1"
    case "$v" in '' | *[!0-9]*)
        printf 'unknown'
        return
        ;;
    esac
    awk -v b="$v" 'BEGIN{u[0]="B/s";u[1]="KiB/s";u[2]="MiB/s";u[3]="GiB/s";i=0;while(b>=1024&&i<3){b/=1024;i++}printf "%.2f %s",b,u[i]}'
}
fmt_bytes() {
    v="$1"
    case "$v" in '' | *[!0-9]*)
        printf 'unknown'
        return
        ;;
    esac
    awk -v b="$v" 'BEGIN{u[0]="B";u[1]="KiB";u[2]="MiB";u[3]="GiB";u[4]="TiB";i=0;while(b>=1024&&i<4){b/=1024;i++}printf "%.2f %s",b,u[i]}'
}
net_gen() {
    t="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    case "$t" in *5G* | *NR*) printf '5G' ;; *4G* | *LTE*) printf '4G' ;; *) printf '%s' "${1:-unknown}" ;; esac
}
unesc() { printf '%s' "$1" | sed 's#\\/#/#g'; }
is_text() { case "${1:-}" in '' | unknown) return 1 ;; *) return 0 ;; esac }
is_uint() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac }
is_sint() { case "${1:-}" in '' | -) return 1 ;; -[0-9]* | [0-9]*) return 0 ;; *) return 1 ;; esac }
append_core() {
    [ -z "${1:-}" ] && return
    core="${core}${core:+
}$1"
}
append_extra() {
    [ -z "${1:-}" ] && return
    extra="${extra}${extra:+
}$1"
}
parse_devices() {
    printf '%s' "$1" | sed 's/},{/}\n{/g' | sed -n 's/.*"mac_addr":"\([^"]*\)".*"hostname":"\([^"]*\)".*"ip_addr":"\([^"]*\)".*/\1|\2|\3/p'
}
quota_bytes() {
    sw="$1"
    size="$2"
    unit="$3"
    fb="$4"
    if [ "$sw" = "1" ] && [ "$unit" = "data" ]; then
        a="${size%_*}"
        b="${size#*_}"
        case "$a:$b" in *[!0-9]*:*) : ;; *:*[!0-9]*) : ;; *)
            [ "$a" != "$size" ] && {
                printf '%s' "$((a * b * 1024 * 1024))"
                return
            }
            ;;
        esac
    fi
    case "$fb" in '' | *[!0-9]*) printf '' ;; *) printf '%s' "$((fb * 1024 * 1024 * 1024))" ;; esac
}
usage() {
    cat <<'EOF'
f50-cli.sh: ZTE F50 网络控制 CLI

用法:
  f50-cli.sh <reconnect|disconnect|connect|status> [参数]
  f50-cli.sh [参数]   # 默认子命令 reconnect

必填参数 (二选一提供：CLI 或环境变量):
  --host <ip-or-host>                     ZTE_HOST
  --password <password>                   ZTE_PASSWORD

功能参数 (CLI > 环境变量):
  --monthly-quota-gb <int>                MONTHLY_QUOTA_GB
    状态页月流量上限回退值，设备未返回上限时使用。
  --help, -h                              显示帮助

示例:
  f50-cli.sh reconnect --host 192.168.10.1 --password '***'
  f50-cli.sh connect --host 192.168.10.1 --password '***'
  f50-cli.sh status --host 192.168.10.1 --password '***'
  ZTE_HOST=192.168.10.1 ZTE_PASSWORD='***' f50-cli.sh
EOF
}

CMD="reconnect"
ZTE_HOST="${ZTE_HOST:-}"
ZTE_PASSWORD="${ZTE_PASSWORD:-}"
# 固定超时与轮询窗口，避免外部参数过多。
HTTP_TIMEOUT=10
WAIT_DISCONNECT=15
WAIT_CONNECT=20
# 设备未返回月流量上限时，用该值补齐进度计算。
MONTHLY_QUOTA_GB="${MONTHLY_QUOTA_GB:-}"
LOCK_DIR="${LOCK_DIR:-/tmp/f50-reconnect.lock}"

if [ $# -gt 0 ]; then
    case "$1" in
    reconnect | disconnect | connect | status)
        CMD="$1"
        shift
        ;;
    help | --help | -h)
        usage
        exit 0
        ;;
    -*) ;;
    *) die "invalid subcommand $1" ;;
    esac
fi

while [ $# -gt 0 ]; do case "$1" in
    --help | -h)
        usage
        exit 0
        ;;
    --host)
        ZTE_HOST="$2"
        shift 2
        ;;
    --password)
        ZTE_PASSWORD="$2"
        shift 2
        ;;
    --monthly-quota-gb)
        MONTHLY_QUOTA_GB="$2"
        shift 2
        ;;
    *) die "unknown arg $1" ;;
    esac done
[ -n "$ZTE_HOST" ] && [ -n "$ZTE_PASSWORD" ] || die "missing ZTE_HOST or ZTE_PASSWORD"

cookie_file="$(mktemp /tmp/zte-cookies.XXXXXX)"
resp_file="/tmp/zte-resp.$$"
lock_held=0
if [ "$CMD" != "status" ]; then
    mkdir "$LOCK_DIR" 2>/dev/null || {
        log "ignored: reconnect already running"
        rm -f "$cookie_file"
        exit 0
    }
    lock_held=1
fi
trap '[ "$lock_held" = "1" ] && rmdir "$LOCK_DIR"; rm -f "$cookie_file" "$resp_file"' EXIT INT TERM
base="http://${ZTE_HOST}"
get_api="${base}/goform/goform_get_cmd_process"
set_api="${base}/goform/goform_set_cmd_process"
hget() { curl -fsS --connect-timeout "$HTTP_TIMEOUT" "$1" -H "Referer: ${base}/index.html" -H 'X-Requested-With: XMLHttpRequest' -H 'User-Agent: Mozilla/5.0' | tr -d '\n'; }
get_json() { hget "${get_api}?isTest=false&cmd=$1&multi_data=1&_=$(($(date +%s) * 1000))"; }
post_json() {
    code="$(curl -sS --connect-timeout "$HTTP_TIMEOUT" -o "$resp_file" -w '%{http_code}' -c "$cookie_file" -b "$cookie_file" "$set_api" -H 'Accept: application/json, text/javascript, */*; q=0.01' -H 'Accept-Language: zh' -H 'Cache-Control: no-cache' -H 'Connection: keep-alive' -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' -H "Origin: ${base}" -H 'Pragma: no-cache' -H "Referer: ${base}/index.html" -H 'User-Agent: Mozilla/5.0' -H 'X-Requested-With: XMLHttpRequest' -H 'dnt: 1' -H 'sec-gpc: 1' --data-raw "$1")" || return 1
    resp="$(cat "$resp_file")"
    [ "$code" = "200" ] || {
        log "http=${code} body=${resp:-empty}"
        return 1
    }
    printf '%s' "$resp" | tr -d '\n'
}

[ "$CMD" = "status" ] || log "step=login"
ld="$(field LD "$(hget "${get_api}?isTest=false&cmd=LD&_=$(($(date +%s) * 1000))")")"
[ -n "$ld" ] || die "missing LD token"
pwd_hash="$(sha_u "$ZTE_PASSWORD")"
login_hash="$(sha_u "${pwd_hash}${ld}")"
login_resp="$(post_json "isTest=false&goformId=LOGIN&user=admin&password=${login_hash}")" || die "login request timeout"
ok "$login_resp" || die "login response ${login_resp:-empty}"

ad=""
v="$(get_json 'Language,cr_version,wa_inner_version')"
ad_seed="$(sha_u "$(field wa_inner_version "$v")$(field cr_version "$v")")"
refresh_ad() {
    rd="$(field RD "$(get_json RD)")"
    [ -n "$rd" ] || die "missing RD token"
    ad="$(sha_u "${ad_seed}${rd}")"
}
with_ad() {
    refresh_ad
    [ -n "$ad" ] && printf '%s&AD=%s' "$1" "$ad" || printf '%s' "$1"
}
read_status() {
    s="$(get_json 'realtime_time,ppp_status,wan_connect_status')"
    rt="$(field realtime_time "$s")"
    ppp="$(field ppp_status "$s")"
    wan="$(field wan_connect_status "$s")"
}
wait_state() {
    target="$1"
    tries="$2"
    i=0
    while [ "$i" -lt "$tries" ]; do
        i=$((i + 1))
        read_status
        log "step=wait_${target} attempt=${i} ppp_status=${ppp:-empty} realtime_time=${rt:-empty} wan=${wan:-empty}"
        [ "$target" = disconnect ] && [ "${ppp:-}" = ppp_disconnected ] && return 0
        if [ "$target" = connect ] && connected "${ppp:-}"; then case "$rt" in '' | *[!0-9]*) : ;; *) [ "$rt" -lt 60 ] && return 0 ;; esac fi
        sleep 1
    done
    return 1
}

do_disconnect() {
    log "step=disconnect submit"
    r="$(post_json "$(with_ad 'isTest=false&notCallback=true&goformId=DISCONNECT_NETWORK')")" || die "disconnect request timeout"
    log "step=disconnect response=${r:-empty}"
    ok "$r" || die "disconnect invalid response ${r:-empty}"
}
do_connect() {
    log "step=connect submit"
    r="$(post_json "$(with_ad 'isTest=false&notCallback=true&goformId=CONNECT_NETWORK')")" || die "connect request timeout"
    log "step=connect response=${r:-empty}"
    ok "$r" || die "connect invalid response ${r:-empty}"
}
do_status() {
    cmd='ppp_status,network_type,network_provider,Operator,spn_name_data,signalbar,realtime_time,realtime_tx_thrpt,realtime_rx_thrpt,realtime_tx_bytes,realtime_rx_bytes,monthly_time,monthly_tx_bytes,monthly_rx_bytes,battery_vol_percent,wifi_access_sta_num,wan_lte_ca,ppp_dial_conn_fail_counter,sim_msisdn,msisdn,dial_mode,data_volume_limit_switch,data_volume_limit_size,data_volume_limit_unit,SSID1,wifi_chip1_ssid1_ssid,LocalDomain,lan_ipaddr,wan_ipaddr,ipv6_wan_ipaddr,wa_inner_version,cr_version,Z5g_rsrp,lte_rsrp,network_rssi'
    s="$(get_json "$cmd")"
    sta_json="$(get_json 'station_list')"
    lan_json="$(get_json 'lan_station_list')"
    operator="$(field network_provider "$s")"
    [ -n "$operator" ] || operator="$(field Operator "$s")"
    [ -n "$operator" ] || operator="$(field spn_name_data "$s")"
    network="$(field network_type "$s")"
    signal="$(field signalbar "$s")"
    realtime="$(field realtime_time "$s")"
    ppp_now="$(field ppp_status "$s")"
    dial="$(field dial_mode "$s")"
    ca="$(field wan_lte_ca "$s")"
    sta="$(field wifi_access_sta_num "$s")"
    sim_num="$(field sim_msisdn "$s")"
    [ -n "$sim_num" ] || sim_num="$(field msisdn "$s")"
    tx="$(field realtime_tx_thrpt "$s")"
    rx="$(field realtime_rx_thrpt "$s")"
    mtime="$(field monthly_time "$s")"
    bat="$(field battery_vol_percent "$s")"
    fail="$(field ppp_dial_conn_fail_counter "$s")"
    mtx="$(field monthly_tx_bytes "$s")"
    mrx="$(field monthly_rx_bytes "$s")"
    sig_dbm="$(field Z5g_rsrp "$s")"
    [ -n "$sig_dbm" ] || sig_dbm="$(field lte_rsrp "$s")"
    [ -n "$sig_dbm" ] || sig_dbm="$(field network_rssi "$s")"
    ssid_name="$(field wifi_chip1_ssid1_ssid "$s")"
    [ -n "$ssid_name" ] || ssid_name="$(field SSID1 "$s")"
    ssid_name="$(unesc "$ssid_name")"
    lan_domain="$(unesc "$(field LocalDomain "$s")")"
    lan_ip="$(field lan_ipaddr "$s")"
    wan_ip="$(field wan_ipaddr "$s")"
    wan_ipv6="$(field ipv6_wan_ipaddr "$s")"
    sw_ver="$(field wa_inner_version "$s")"
    [ -n "$sw_ver" ] || sw_ver="$(field cr_version "$s")"
    sw_ver="$(unesc "$sw_ver")"
    used=""
    is_uint "$mtx" && is_uint "$mrx" && used="$((mtx + mrx))"
    qbytes="$(quota_bytes "$(field data_volume_limit_switch "$s")" "$(field data_volume_limit_size "$s")" "$(field data_volume_limit_unit "$s")" "$MONTHLY_QUOTA_GB")"
    pct=""
    is_uint "$used" && is_uint "$qbytes" && [ "$qbytes" -gt 0 ] && pct="$(awk -v u="$used" -v q="$qbytes" 'BEGIN{printf "%.1f%%", (u*100)/q}')"
    dev_raw="$({
        parse_devices "$sta_json"
        parse_devices "$lan_json"
    } | awk '!seen[$0]++')"
    dev_count="$(printf '%s\n' "$dev_raw" | awk 'NF{c++}END{print c+0}')"
    dev_lines=""
    if [ "$dev_count" -gt 0 ]; then
        n=0
        while IFS='|' read -r mac host ip; do
            [ -z "${mac}${host}${ip}" ] && continue
            n=$((n + 1))
            [ -n "$host" ] || host="unknown"
            line="${n}. ${host}${ip:+ ($ip)}${mac:+ [$mac]}"
            dev_lines="${dev_lines}${dev_lines:+
}${line}"
        done <<EOF
$dev_raw
EOF
    fi
    core=""
    extra=""
    is_text "$operator" && append_core "运营商: $operator"
    is_text "$network" && append_core "网络: $(net_gen "$network") ($network)"
    is_uint "$signal" && append_core "信号: ${signal}/5"
    is_sint "$sig_dbm" && append_core "信号强度: ${sig_dbm} dBm"
    is_text "$ppp_now" && append_core "连接状态: $ppp_now"
    is_uint "$realtime" && append_core "当前连接时长: $(fmt_dur "$realtime")"
    is_text "$sim_num" && append_core "SIM 号码: $sim_num"
    is_text "$ssid_name" && append_core "网络名称: $ssid_name"
    is_text "$lan_domain" && append_core "局域网域名: $lan_domain"
    is_text "$lan_ip" && append_core "IP 地址: $lan_ip"
    is_text "$wan_ip" && append_core "WAN IP: $wan_ip"
    is_text "$wan_ipv6" && append_core "WAN IPv6: $wan_ipv6"
    is_text "$sw_ver" && append_core "软件版本: $sw_ver"
    is_uint "$tx" && append_extra "实时上行: $(fmt_rate "$tx")"
    is_uint "$rx" && append_extra "实时下行: $(fmt_rate "$rx")"
    is_text "$dial" && append_extra "拨号模式: $dial"
    is_text "$ca" && append_extra "LTE CA: $ca"
    is_uint "$sta" && append_extra "Wi-Fi 接入数: $sta"
    [ "$dev_count" -gt 0 ] && append_extra "当前接入设备: $dev_count 台"
    [ "$dev_count" -gt 0 ] && append_extra "设备列表:
$dev_lines"
    is_uint "$mtx" && append_extra "本月上行: $(fmt_bytes "$mtx")"
    is_uint "$mrx" && append_extra "本月下行: $(fmt_bytes "$mrx")"
    is_uint "$used" && append_extra "本月总流量: $(fmt_bytes "$used")"
    is_uint "$qbytes" && append_extra "月流量上限: $(fmt_bytes "$qbytes")"
    is_text "$pct" && append_extra "月流量进度: $pct"
    is_uint "$mtime" && append_extra "月在线时长(秒): $mtime"
    is_uint "$bat" && append_extra "电量: $bat"
    is_uint "$fail" && append_extra "拨号失败计数: $fail"
    missing=""
    is_sint "$sig_dbm" || missing="${missing}${missing:+, }信号强度(dBm)"
    is_text "$ssid_name" || missing="${missing}${missing:+, }网络名称"
    is_text "$lan_domain" || missing="${missing}${missing:+, }局域网域名"
    is_text "$lan_ip" || missing="${missing}${missing:+, }IP地址"
    is_text "$wan_ip" || missing="${missing}${missing:+, }WAN IP"
    is_text "$wan_ipv6" || missing="${missing}${missing:+, }WAN IPv6"
    is_text "$sw_ver" || missing="${missing}${missing:+, }软件版本"
    [ -n "$missing" ] && append_extra "未获取字段: $missing"
    [ -n "$core" ] || core="暂无可用状态数据"
    if has_cmd gum && [ -t 1 ]; then
        gum style --border rounded --padding "1 2" --margin "1 0" \
            "F50 Status" "$core"
        [ -n "$extra" ] && gum style --border rounded --padding "1 2" "$extra"
    else
        printf '%s\n' "F50 状态" "$core"
        [ -n "$extra" ] && printf '\n%s\n' "$extra"
    fi
}

case "$CMD" in
status) do_status ;;
disconnect)
    do_disconnect
    wait_state disconnect "$WAIT_DISCONNECT" || true
    ;;
connect)
    do_connect
    wait_state connect "$WAIT_CONNECT" || true
    ;;
reconnect)
    do_disconnect
    wait_state disconnect "$WAIT_DISCONNECT" || die "disconnect state timeout"
    do_connect
    wait_state connect "$WAIT_CONNECT" || die "connect state timeout"
    ;;
*) die "invalid subcommand ${CMD}" ;;
esac
[ "$CMD" = "status" ] || log "accepted: mode=${CMD} ppp_status=${ppp:-unknown} realtime_time=${rt:-unknown}"
