# TVBox daed 配置经验

本文从 [22-tvbox-bypass-router.md](22-tvbox-bypass-router.md) 拆出，只记录 daed 相关经验。

## daed 与 ophub 内核 BTF 支持情况

daed 需要内核开启 CONFIG_DEBUG_INFO_BTF 才能加载 eBPF 程序。ophub 的 kernel_flippy 和 kernel_stable 在不同内核版本上的 BTF 支持不同（数据来自 [ophub/kernel kernel-config](https://github.com/ophub/kernel/tree/main/kernel-config/release/stable)）：

| 内核版本 | kernel_flippy | kernel_stable |
|---|---:|---:|
| 5.4 | 无 BTF | 无 BTF |
| 5.10 | 无 BTF | 无 BTF |
| 5.15 | 无 BTF | 有 BTF |
| 6.1 | 无 BTF | 无 BTF |
| 6.6 | 无 BTF | 无 BTF |
| 6.12 | 无 BTF | **有 BTF** |
| 6.18 | 无 BTF | **有 BTF** |

当前构建设置：`kernel_usage: flippy` + `openwrt_kernel: 6.6.y`，6.6 内核没有 BTF。

**决策记录**：改为 `kernel_usage: stable` + `openwrt_kernel: 6.12.y`。
原因：stable 6.12 是唯一原生支持 BTF 的内核，daed 需要 BTF 才能工作。风险是 6.12 在 HK1 Box 上未充分测试，如果遇到兼容性问题再考虑回退或自编译内核。

Workflow 已新增 `kernel_usage` 输入选项，可以在 UI 上选择 flippy 或 stable。

## daed 与 Hysteria2 obfs 兼容性

当前 daed 可以导入 `hysteria2://` 节点，但 dae 核心的 Hysteria2 URL 解析未实现 Salamander 混淆。节点如果依赖：

```text
obfs=salamander
obfs-password=...
```

会表现为节点超时，而不是参数报错。

已验证现象：

```text
节点测试错误：Head "http://cp.cloudflare.com": connect error: timeout: no recent network activity
发往 hy2 服务器 UDP 包：有
来自 hy2 服务器 UDP 回包：少量
结果：QUIC/Hysteria2 握手未建立
```

源码证据：`daeuniverse/outbound` 的 `dialer/hysteria2/hysteria2.go` 标注 `TODO: support salamander obfuscation`，解析函数只处理 `insecure`、`sni`、`pinSHA256`、`ca`、`maxTx`、`maxRx`，不处理 `obfs` / `obfs-password`。

结论：当前 TVBox 上的 daed 不适合使用带 Salamander obfs 的 hy2 节点。要用 daed + hy2，应给服务端单独开不带 obfs 的 hy2 节点：

```text
hysteria2://密码@域名:端口/?sni=域名&insecure=1#hy2-no-obfs
```

## daed DNS 与路由经验

本次排查确认：dae 会拦截目标端口 53 的 UDP 并嗅探 DNS。旁路由上不能只看客户端配置的 DNS 地址，还要确认 OpenWrt dnsmasq 是否把 DNS 请求重定向回本机。

### dnsmasq DNS 重定向会绕开 daed DNS

当前采用的旁路由 DNS 模型：主路由 DHCP 下发 `gateway=<TVBOX_IP>`，DNS 下发外部地址（例如 `8.8.8.8`），让客户端 DNS 流量经过 TVBox 转发路径，由 daed 的 `dport(53) -> direct` 进入 dae DNS 模块。

如果 TVBox 上 `dhcp.@dnsmasq[0].dns_redirect='1'`，OpenWrt 会把客户端发往外部 DNS 的请求重定向到 TVBox 本机 dnsmasq。结果链路变成：

```text
Client → 8.8.8.8:53 → TVBox dnsmasq → dnsmasq 上游
```

而不是：

```text
Client → 8.8.8.8:53 → daed DNS routing
```

实测表现：`dig @8.8.8.8 cli-proxy-api.<MAIN_DOMAIN>` 返回 Cloudflare 的 `NXDOMAIN`，`www.google.com` 解析到污染 IP（如 `69.171.235.22` / `104.244.42.197` / `2001::1`），curl 连接超时。

修复：关闭 dnsmasq 的 DNS 重定向，重启防火墙后重启 daed，让 eBPF 重新挂载。

```sh
uci set dhcp.@dnsmasq[0].dns_redirect='0'
uci commit dhcp
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
/etc/init.d/daed restart
```

验证：

```sh
dig @8.8.8.8 cli-proxy-api.<MAIN_DOMAIN> A
# 期望：CNAME homelab-internal.<MAIN_DOMAIN>，A 记录为内网地址

dig @8.8.8.8 www.google.com A
# 期望：Google 正常地址，不是污染 IP

curl -4 -I --connect-timeout 8 https://www.google.com
# 期望：HTTP/2 200
```

`direct` 与 `must_direct` 对 DNS 的语义不同：

- `direct`：DNS 请求进入 dae DNS 模块，可保留 domain routing 所需信息。
- `must_direct`：DNS 请求不进入 dae DNS 模块，适合避免本机 DNS 回环。

推荐旁路由顺序：

```dae
pname(dnsmasq) && dport(53) -> must_direct
sip(<TVBOX_IP>) && dport(53) -> must_direct
dport(53) -> direct
l4proto(udp) && dport(443) -> block
l4proto(udp) && !dport(53) -> direct
```

含义：

- dnsmasq 与 TVBox 本机 DNS 排障流量直连，避免回环和便于测试。
- LAN 客户端 DNS 仍交给 dae DNS 模块，保证按域名分流。
- UDP/443 先 block，避免浏览器 QUIC/HTTP3 首次探测干扰。
- 其他非 DNS UDP 直连，避免 Tailscale、WebRTC、游戏等 UDP 被代理后不稳定。

规则顺序很重要。`l4proto(udp) -> direct` 如果放在 `l4proto(udp) && dport(443) -> block` 前面，会让 QUIC block 永远不生效。

## daed DNS 上游建议

当前更适合的结构：

```text
LAN 客户端 DNS → 外部 DNS 地址（如 8.8.8.8）→ TVBox 网关转发路径 → daed DNS routing
内网域名 → 主路由 DNS
国内域名 → 国内 UDP DNS
国外域名 → DoH over proxy
节点/订阅域名 bootstrap → 本机 dnsmasq
```

示例：

```dae
upstream {
  router: 'udp://<MAIN_ROUTER_IP>:53'
  alidns: 'udp://223.5.5.5:53'
  foreign: 'https://cloudflare-dns.com:443/dns-query'
}

routing {
  request {
    qtype(https) -> reject
    qname(suffix: <MAIN_DOMAIN>) -> router
    qname(suffix: lan) -> router
    qname(geosite:cn) -> alidns
    fallback: foreign
  }
  response {
    upstream(router) -> accept
    upstream(foreign) -> accept
    fallback: accept
  }
}
```

同时在全局配置里设置：

```text
bootstrap_resolver: 127.0.0.1:53
fallback_resolver: 127.0.0.1:53
dial_mode: domain++
sniffing_timeout: 300ms~500ms
```

原因：daed 自己解析节点域名、订阅域名、DoH upstream 域名时会用 bootstrap resolver；空配置会回退到默认公共 DNS，在当前网络下不稳定。本机 dnsmasq 已能解析 `<NODE_DOMAIN>` 时，bootstrap/fallback 指向 `127.0.0.1:53` 更稳。

`cloudflare-dns.com` 这类 DoH upstream 域名要在 routing 中走代理：

```dae
domain(full: cloudflare-dns.com) -> proxy
```

否则 DoH 可能直连不稳定的 Cloudflare DNS 链路。

## daed 健康检查与 IPv6

TVBox 可以通过主路由中继获得公网 IPv6。需要单独创建 DHCPv6 client 接口：

```text
interface: lan6
proto: dhcpv6
device: @lan
reqaddress: try
reqprefix: no
```

验证：

```sh
ip -6 addr show br-lan scope global
ip -6 route show default
ping -6 -c 2 2606:4700:4700::1111
```

如果公网 IPv6 出口丢包高，不要用 IPv6 字面量做 daed 健康检查。保留 TVBox IPv6 支持，但健康检查可先只用 IPv4 目标，避免把主路由 IPv6 出口抖动误判成节点不可用。

`check_tolerance` 不要长期保持 `0s`。`min_moving_avg` 组在节点延迟轻微波动时会频繁切换。可先设为：

```text
check_tolerance: 100ms
```

官方语义是：只有新节点延迟小于等于旧节点延迟减去 tolerance 时才切换。
