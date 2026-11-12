# 路由器 DNS 配置

路由器 dnsmasq 的配置整份由 [nix-config](https://github.com/shelken/nix-config) 的 `hosts/router-mine/` 声明，用 nuci 下发；home-ops 不再下发任何 dnsmasq 文件，决策见 [ADR-0009](../adr/0009-router-dnsmasq-declared-in-nix-config.md)。

## 规则

| 规则 | 作用 |
| :--- | :--- |
| `server=/<主域>/<k8s-gateway>`、`server=/<内部域>/<k8s-gateway>` | 集群服务名称转给 k8s-gateway |
| `address=/<自举名>/<地址>`，配合 `address_as_local=1` | 集群外自举名称本地权威应答，A 与 AAAA 都不转发，不依赖集群 |

声明在 nix-config 的 `hosts/router-mine/home-ops/dns.nix`。自举名集合对应 nix-config 的 `hosts/sakamoto/apps/configs/caddy/Caddyfile` 里 `internal-access` 的站点：那边加一个站点，这里加一个名字。后端选择见 [集群服务 DNS 决策](../adr/0003-internal-dns-via-gateway.md)。

## 验证

```bash
ssh <ROUTER> 'uci show dhcp.@dnsmasq[0] | grep -E "\\.(server|address|address_as_local)="'
dig @<ROUTER_IP> <CLUSTER_SERVICE_IN_MAIN_DOMAIN> A
dig @<ROUTER_IP> <BOOTSTRAP_NAME> A
```

集群不可用时，集群服务名称无法解析；集群外自举名称仍由路由器本地回答

判断解析失败原因前，先确认失败进程用的是哪个解析器：musl 报 `Try again` 或 `Name does not resolve`，glibc 报 `Temporary failure in name resolution`，Go 纯解析器不会输出这些文本。musl 的 `getaddrinfo` 对 A/AAAA 任一失败即判整名失败，报错文本本身就指向解析器类型

```bash
ssh <NODE> 'grep "trying next host" /var/lib/rancher/k3s/agent/containerd/containerd.log | tail -n 20'
```

k3s containerd 的逐端点失败与回退只写进 `containerd.log`，不进 journal，排查镜像拉取时不要只看 `journalctl`
