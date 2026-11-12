---
date: 2026-11-13
status: accepted
---

# 路由器 dnsmasq 的 DNS 分流与自举记录由 nix-config 声明

路由器 `/etc/config/dhcp` 整份由 nix-config 的 `hosts/router-mine/` 用 nuci 声明式下发。home-ops 原先独占的 dnsmasq 专用目录和 `/etc/dnsmasq.conf` 里的机器级接入点不再需要：dnsmasq 的 UCI 原生选项 `server`（集群域转给 k8s-gateway）与 `address` 配合 `address_as_local`（自举名的 A、AAAA 都在本地闭合）能完整表达同样的规则。[ADR-0003](./0003-internal-dns-via-gateway.md) 中关于路由器 dnsmasq 所有权的部分由本 ADR 取代，k8s-gateway 动态应答与自举名称不依赖集群的决定不变

## Considered Options

- 继续由 home-ops 下发专用目录：同一台路由器的 dnsmasq 存在两个所有者，UCI 之外还要多维护一个接入点
- 用 nuci 的 `files` 下发两个文件：`files` 只写不删，文件变化不触发重载，仍然要接入点

## Consequences

- 自举名的事实来源是 nix-config 的 `hosts/router-mine/home-ops/dns.nix`，入口 IP 变化时改那里
- home-ops 不再提供 `task router:dns:*`，仓库里也没有 `router/dnsmasq/`
- 路由器 dhcp 配置变更后 dnsmasq 重载，有几秒解析不可用
