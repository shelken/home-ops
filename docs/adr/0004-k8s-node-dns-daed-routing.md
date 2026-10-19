---
date: 2026-10-04
status: accepted
---

# K8s 节点显式指定外部 DNS 触发旁路由嗅探

K8s 节点的 systemd-networkd 主网卡显式配置 `DNS=1.1.1.1 8.8.8.8` 并禁用 `[DHCPv4] UseDNS`，让节点 DNS 必须跨三层网关到达旁路由 daed，触发 eBPF 域名嗅探，境外服务不再被 GFW SNI 重置。配置收敛在 `ansible/playbooks/tasks/k8s-dns.yaml`，主路由 DHCP 与局域网普通设备维持现状

daed 分流规则、白名单与 DNS 重定向的实测依据，以及三条被否决方案（主路由全局下发 Option 6、沿用主路由 DNS、改用 `223.5.5.5`）的原因见 [TVBox daed 配置经验](../23-daed-on-tvbox.md)。节点 DNS 策略的运维入口见 [DNS 设置记录](../dns-settings.md)

## Consequences

- 节点访问 GitHub、Quay、GHCR 等境外服务命中 daed 代理，依赖旁路由 TVBox 正常运行
- 内网域名经 daed 回弹主路由解析，不影响集群自举与局域网通信
- 各节点默认路由原本就指向旁路由，此改动未引入新增单点故障
