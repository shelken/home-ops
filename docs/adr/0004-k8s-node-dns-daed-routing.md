---
date: 2026-10-04
status: accepted
---

# K8s 节点 DNS 显式指向外部地址，经旁路由 dae 解析

K8s 节点的主网卡 DNS 固定为 `1.1.1.1 8.8.8.8` 并忽略 DHCP 下发的 DNS，使查询必须跨三层网关到达旁路由，进入 dae 的 DNS 模块按域名分流：境外域名经代理 DoH，境内域名走国内 DNS，内网域名回弹主路由。节点若沿用 DHCP 下发的主路由 DNS，查询经二层直达主路由，不经过旁路由。配置在 `ansible/playbooks/tasks/k8s-dns.yaml`，运维见 [dns-settings](../dns-settings.md)

## Considered Options

- 主路由 DHCP 全局下发 Option 6：dae 配有客户端白名单（`!mac(...) && !sip(...) -> must_direct`），非白名单设备的 DNS 查询会直连公网，被污染且失去 `.lan` 与 `*.int` 解析
- 指定 `223.5.5.5`：dae 对它 `dip(223.5.5.5) && dport(53) -> must_direct`，查询跳过 DNS 模块，拿到国内污染 IP
- 选 `1.1.1.1` 与 `8.8.8.8`：它们是公网非 CN 地址，访问必须走默认网关到旁路由；配置两个作备用，不混入内网或阿里 DNS，避免切换后失效

## Consequences

- 节点解析依赖旁路由运行，节点 IPv4 默认路由本来就指向旁路由，没有新增单点
- 节点解析集群自举服务（`*.int.<MAIN_DOMAIN>`）和局域网（`*.lan`）时，由 dae 转回主路由，内网通信不受影响
- 节点的 IPv6 出网不在本决策范围，见 [ADR-0005](0005-k8s-node-no-ipv6-egress.md)
- 因果更正：该决策最初认为节点 DNS 绕过旁路由会让境外流量未被嗅探、被 GFW SNI 重置，该因果已被实测推翻。未嗅探到域名的 TCP 仍按 routing 末端的 fallback 走代理，断流来自 dae 的客户端白名单排除，见 [23-daed-on-tvbox.md](../23-daed-on-tvbox.md) 的白名单小节
