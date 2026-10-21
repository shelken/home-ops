# K8s 节点不使用 RA 下发的 IPv6 默认网关，出网只走 IPv4 经旁路由

K8s 节点的 systemd-networkd drop-in 对所有网卡设置 `[IPv6AcceptRA] UseGateway=false`，节点没有 IPv6 默认路由，访问境外双栈服务（Codeberg、GitHub、镜像仓库）时 IPv6 立即失败并回退 IPv4，经旁路由 daed 出网。承接 [ADR-0004](0004-k8s-node-dns-daed-routing.md)：节点的 IPv4 默认路由与 DNS 已指向旁路由，IPv6 此前是唯一绕过旁路由的出口。

## 背景

- 主路由 `ra=relay`、`ndp=relay`，WAN 侧 dhcpv6 不拿前缀（`delegate=0`），v6 NAT 关闭。节点从 RA 学到指向主路由的 IPv6 默认路由，并持有 F50 下发的公网地址。
- 节点优先选 AAAA，境外双栈服务的流量绕过 daed 直连 F50，被限速到约 35 KB/s，曾导致 Helm 5 分钟超时与回滚，现象为 `curl -6` 超时而 `curl -4` 正常。
- Cilium `enable-ipv6=false`，Pod 全是 IPv4，没有 `hostNetwork` 工作负载。IPv6 出网的使用者只有节点自身（containerd、kubelet、apt、ansible）。
- 需要 IPv6 直连的 Pod（caddy-external、tailscale、qbittorrent、ss-rust）通过 `multus-ipv6` 的 macvlan 在自己的网络命名空间里拿到独立 GUA 和 RA 默认路由，入站由主路由防火墙按 Pod 地址放行，不经过节点路由表。

## Considered Options

- **节点 IPv6 默认路由改指旁路由的链路本地地址**：实测下载速度提升约 50 倍，但需由 Ansible 从 IPv4 网关 MAC 推导 EUI-64 地址，绑定旁路由的寻址方式；旁路由自己的 IPv6 出口同样走 F50，docs/23 已记录丢包较高；更换旁路由实现后地址会变。节点没有 IPv6 业务需求，不值得承担这些复杂度
- **主路由对节点做策略路由转发 IPv6**：旁路由有客户端白名单（`!mac(...) && !sip(...) -> must_direct`），且主路由处于 RA relay 模式，无法在主路由侧可靠分流
- **主路由改为 RA server + NAT6**：会破坏 `multus-ipv6` Pod 依赖的 GUA 直连与入站，且需要 WAN 侧前缀委派，当前拿不到
- **禁用节点网卡 IPv6**：连带失去 on-link IPv6，改动面比只去掉默认网关大

## 后果

- 节点不再有 off-link IPv6：无法从外网经 IPv6 连到节点自身，也无法用 IPv6 访问外网。主路由防火墙本来就只放行 Pod 的 EUI-64 地址，不放行节点，实际可达性不变
- 节点 on-link（LAN 内）IPv6 保留；`multus-ipv6` Pod 的 IPv6 出入站不受影响
- 配置由 `ansible/playbooks/tasks/k8s-dns.yaml` 统一下发。撤销该项后，下一次 RA 会自动恢复默认路由
- 若将来要让节点 IPv6 经旁路由或其他网关出网，回到第一个选项
