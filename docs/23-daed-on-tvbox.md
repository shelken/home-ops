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

**决策记录**：构建改为 `kernel_usage: stable` + `openwrt_kernel: 6.12.y`。
原因：stable 6.12 是唯一原生支持 BTF 的内核，daed 需要 BTF 才能工作。风险是 6.12 在 HK1 Box 上未充分测试，如果遇到兼容性问题再考虑回退或自编译内核。

Workflow 有 `kernel_usage` 输入选项，可以在 UI 上选择 flippy 或 stable。

## daed 与 Hysteria2 obfs 兼容性

当前 daed 可以导入 `hysteria2://` 节点，但 dae 核心的 Hysteria2 URL 解析未实现 Salamander 混淆。节点如果依赖：

```text
obfs=salamander
obfs-password=...
```

会表现为节点超时，而不是参数报错。

判据是 UDP 有发无回，QUIC 握手始终不建立。

源码证据：`daeuniverse/outbound` 的 `dialer/hysteria2/hysteria2.go` 标注 `TODO: support salamander obfuscation`，解析函数只处理 `insecure`、`sni`、`pinSHA256`、`ca`、`maxTx`、`maxRx`，不处理 `obfs` / `obfs-password`。

结论：当前 TVBox 上的 daed 不适合使用带 Salamander obfs 的 hy2 节点。要用 daed + hy2，应给服务端单独开不带 obfs 的 hy2 节点：

```text
hysteria2://密码@域名:端口/?sni=域名&insecure=1#hy2-no-obfs
```

## daed DNS 与路由经验

本次排查确认：dae 会拦截目标端口 53 的 UDP 并嗅探 DNS。旁路由上不能只看客户端配置的 DNS 地址，还要确认 OpenWrt dnsmasq 是否把 DNS 请求重定向回本机。

### dnsmasq DNS 重定向会绕开 daed DNS

主路由的 `lan` 网络只下发 option 3（`<TVBOX_IP>`）与 option 121 classless route，没有 option 6；读当前值用 `uci show dhcp`。客户端因此把主路由自身当作 DNS，该地址与客户端同网段，查询经二层直达主路由，不经过 TVBox，也就不会命中 daed 的 `dport(53) -> direct`。

要让客户端 DNS 进入 dae DNS 模块，得由客户端显式指定一个非同网段的外部 DNS 地址（例如 `8.8.8.8`），该地址才会走默认网关送到 TVBox。

如果 TVBox 上 `dhcp.@dnsmasq[0].dns_redirect='1'`，OpenWrt 会把客户端发往外部 DNS 的请求重定向到 TVBox 本机 dnsmasq。结果链路变成：

```text
Client → 8.8.8.8:53 → TVBox dnsmasq → dnsmasq 上游
```

而不是：

```text
Client → 8.8.8.8:53 → daed DNS routing
```

表现为内网域名解析不到，境外域名拿到污染结果，curl 连接超时。

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

### 白名单外的主机整机不进入 daed

daed 的客户端白名单规则是 `!mac(...) && !sip(...) -> must_direct`。不在白名单内的主机，全部流量在 eBPF 层被标记为 `must_direct`，既不进入 dae 的路由规则，也不进入 dae DNS 模块。

验证方式：非白名单主机经本机代理访问境外站点，同一时间窗内 daed 日志对该主机零记录，白名单主机的同类请求记为 `outbound=proxy`。

白名单外的主机不在本机跑代理客户端时完全裸连，国内站点可达。被墙站点一律超时：

```sh
curl -4 -I --connect-timeout 8 https://www.baidu.com
curl -4 -I --connect-timeout 8 https://www.google.com
```

早期把这一现象归因于「客户端与主路由同网段，DNS 走二层直达，daed 嗅探不到域名」。该归因不成立：未嗅探到域名的外来 TCP 仍按 routing 末端的 fallback 走代理，真正短路的是白名单规则。

注意防范以下误区：

1. **不能在主路由全局 DHCP 下发 Option 6（如 8.8.8.8）**：daed 配有客户端白名单（`!mac(...) && !sip(...) -> must_direct`）。全局下发会导致非白名单普通设备（手机、电视、IoT）的 DNS 查询直连公网，不仅遭受 GFW 投毒污染，而且彻底失去 `.lan` 与 `*.int` 内网解析。
2. **不能指定 223.5.5.5 作为触发 IP**：daed 规则中硬编码了 `dip(223.5.5.5) && dport(53) -> must_direct`，发往该地址的 DNS 请求会被跳过嗅探，直连拿到国内污染 IP。
3. **K8s 节点由 Ansible 统一收口**：在 `ansible/playbooks/tasks/k8s-dns.yaml` 中将主网卡显式配置为 `DNS=1.1.1.1 8.8.8.8` 并禁用 `[DHCPv4] UseDNS`。内网域名由 daed 的 DNS 规则自动回弹主路由，境外域名由 daed 加密 DoH 嗅探代理。具体权衡见 [ADR-0004](adr/0004-k8s-node-dns-daed-routing.md)。

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
