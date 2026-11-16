---
date: 2026-11-17
status: accepted
---

# K8s 节点 DNS 直接指向旁路由

K8s 节点主网卡的 DNS 直接填旁路由地址，并忽略 DHCP 下发的 DNS。旁路由的 sing-box 在 53 端口提供 DNS（`dns-in`），按域名分流：境外域名经代理 DoH，境内域名走国内 DNS，内网域名转回主路由。地址取自 nix-config 的 `vars/networking.nix`，配置在 `hosts/k8s/common.nix`，运维见 [dns-settings](../dns-settings.md)。取代 [ADR-0004](./0004-k8s-node-dns-daed-routing.md)

## Considered Options

- 沿用 ADR-0004 的 `1.1.1.1 8.8.8.8`：查询经默认网关到达旁路由后被劫持进 DNS 模块，结果相同，但配置写的是公网地址，真实意图藏在「53 端口劫持」这条隐含机制里
- 主路由 DHCP 全局下发 Option 6：旁路由有客户端白名单，名单外设备拿不到分流结果；节点也不该依赖主路由的 DHCP 选项
- 指定 `223.5.5.5`：旁路由对它直接放行，查询跳过 DNS 模块，拿到国内污染 IP

## Consequences

- 节点解析依赖旁路由运行。节点 IPv4 默认路由本来就指向旁路由，没有新增单点
- 旁路由的 DNS 白名单按源 IP 匹配，节点必须留在白名单内（nix-config 的 `hosts/hk1box/sing-box.nix`），否则拿不到分流结果
- 节点的 IPv6 出网不在本决策范围，见 [ADR-0005](./0005-k8s-node-no-ipv6-egress.md)
