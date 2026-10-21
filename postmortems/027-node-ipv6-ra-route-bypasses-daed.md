# Node IPv6 RA default route bypasses daed

**日期**: 2026-10-22
**影响**: k8s-gateway 升级时 containerd 从 Codeberg 拉镜像被限速到约 35 KB/s，Helm 5 分钟超时并回滚，DNS 一度中断；排查中先后提出了绑定旁路由的 IPv6 静态路由方案和含糊的「入站受影响」结论，多花了几轮确认
**发现人**: 用户

## 问题

K8s 节点的 IPv4 默认路由和 DNS 早已指向旁路由 daed（ADR-0004），但节点同时从主路由的 RA 学到了 IPv6 默认路由。境外双栈服务优先走 AAAA，流量绕过 daed 直连 F50，被限速。ADR-0004 的「全节点经旁路由」只覆盖了 IPv4 与 DNS，IPv6 一直是缺口

## 现象

最小复现命令，在任一节点上执行：

```bash
ip -6 route show default
ip -4 route show default
curl -6 -s -o /dev/null -w '%{http_code} %{time_total}s\n' -m 8 https://codeberg.org
curl -4 -s -o /dev/null -w '%{http_code} %{time_total}s\n' -m 8 https://codeberg.org
```

关键输出：

```txt
default via <MAIN_ROUTER_LL> dev eth1 proto ra metric 100
default via <BYPASS_ROUTER_IP> dev eth1 proto dhcp metric 100
curl -6 -> 000 (8 秒超时)
curl -4 -> 200
```

## 根因

错误假设：

- 以为 IPv4 默认路由和 DNS 指向旁路由，节点出网就整体经过旁路由。IPv4 与 IPv6 各有独立的默认路由来源（DHCP option 3/121 与 RA），只对齐了前者
- 以为必须让节点 IPv6 也经过旁路由。实际 Cilium `enable-ipv6=false`、Pod 全是 IPv4，节点自身是 IPv6 出网的唯一使用者，没有业务需求，经 daed 转发只增加复杂度
- 以为去掉节点默认网关会影响 `multus-ipv6` 的 Pod 和入站。实际这些 Pod 的 macvlan 子接口在自己的网络命名空间里有独立 GUA 与 RA 默认路由，入站由主路由防火墙按 Pod 的 EUI-64 地址放行，不经过节点路由表。节点自身的 GUA 也本来就不在放行列表里
- 以为 `tags` 写在 `include_tasks` 上会作用到被引入的任务。`include_tasks` 是动态引入，标签只作用于 include 本身，`--tags dns` 会把整段 DNS 任务跳过

实际约束：

- 主路由 `ra=relay`、`ndp=relay`，WAN 侧不拿前缀，v6 NAT 关闭，无法在主路由侧按客户端分流
- 旁路由 daed 有客户端白名单，且它自己的 IPv6 出口同样走 F50

缺失检查点：

- 排查「境外服务慢」时只检查了 IPv4 路由与 DNS，没有对比 `curl -4` 与 `curl -6`
- 评估影响面前没有先查 Cilium 是否启用 IPv6、谁在使用节点的 IPv6
- 报告「入站受影响」前没有查主路由防火墙实际放行了哪些地址
- 新写的 playbook 标签没有先用 `--list-tasks` 或 `--tags ... --check` 确认内部任务被选中

## 修复

- 节点所有网卡的 networkd drop-in 设置 `[IPv6AcceptRA] UseGateway=false`，节点没有 IPv6 默认路由，IPv6 立即失败并回退 IPv4 经旁路由，取舍记录在 [ADR-0005](../docs/adr/0005-k8s-node-no-ipv6-egress.md)
- drop-in 变更后立即应用 networkd，并在残留 RA 默认路由时删除，见 `ansible/playbooks/tasks/k8s-dns.yaml`
- `setup-network.yaml` 的 `include_tasks` 改为 `import_tasks`，`--tags` 对内部任务生效
- 验证：三个节点 `ip -6 route show default` 为空，`curl -6` 0.2 秒内失败，`curl -4` 返回 200，caddy-external 与 ss-rust 的 IPv6 入站仍可达，`--tags dns` 二次运行 `changed=0`

## 预防

- 排查「境外服务慢或超时」先在节点上对比 `curl -4` 与 `curl -6`，再看路由与 DNS
- 新增或修改节点出网策略时，同时检查 IPv4 与 IPv6 的默认路由来源，命令为 `ip -4 route show default` 与 `ip -6 route show default`
- 评估「去掉某条路由或网关会影响谁」前，先确认三件事：Cilium 是否启用 IPv6（`kubectl -n kube-system get cm cilium-config -o yaml | grep enable-ipv6`），multus Pod 的路由在哪个网络命名空间，主路由防火墙放行了哪些目的地址
- 给 `include_tasks` 打 `tags` 无效，需要按标签选择任务时一律用 `import_tasks`
- 修改 playbook 标签后，先执行 `ansible-playbook <playbook> --tags <tag> --list-tasks`，确认内部任务出现在列表里
