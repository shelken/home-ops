# K8s 节点 DNS 与 IPv6 出网策略

适用于 inventory `k8s` 组的全部节点。由 `ansible/playbooks/tasks/k8s-dns.yaml` 下发，入口是 `setup-network.yaml` 的 `dns` tag，落地为每个 netplan 网卡的 systemd-networkd drop-in `ansible-dns.conf`

## 策略

| 对象 | 设置 |
|---|---|
| 默认 IPv4 路由网卡 | `DNS=1.1.1.1 8.8.8.8`、`DNSDefaultRoute=true` |
| 其他网卡 | `DNSDefaultRoute=false` |
| 所有网卡 | 忽略 DHCPv4、DHCPv6、RA 下发的 DNS；忽略 RA 的搜索域；RA 不提供默认网关 |

每次下发还会删除节点已学到的 RA IPv6 默认路由，并清理旧版本留下的 drop-in 文件

## 原因

- **DNS 指向 1.1.1.1 与 8.8.8.8**：这两个地址与节点不同网段，查询必须经默认网关到达旁路由，进入 dae 的 DNS 模块，按域名分流；内网域名由 dae 转回主路由解析。节点若沿用主路由 DHCP 下发的 DNS，查询经二层直达主路由，绕过旁路由。取舍与被否决的方案见 [ADR-0004](adr/0004-k8s-node-dns-daed-routing.md)，旁路由侧的限制见 [23-daed-on-tvbox.md](23-daed-on-tvbox.md)
- **忽略 DHCPv6 与 RA 的 DNS**：节点曾从 IPv6 RA/DHCPv6 拿到运营商 DNS，解析被污染
- **不接受 RA 默认网关**：节点从 RA 学到的 IPv6 默认路由绕过旁路由，境外双栈服务被限速直连，曾导致 Helm 超时回滚。取舍见 [ADR-0005](adr/0005-k8s-node-no-ipv6-egress.md)

## 不做的事

- 不修改 IP、网关、DHCP/static 模式、cloud-init 或 netplan 网络形态：Lima 节点的网卡归 Lima/cloud-init，PVE 节点归 cloud-init，这里只写 DNS 与 RA 的 drop-in
- 不在主路由全局下发 DHCP DNS：非白名单设备的查询会直连公网，被污染并失去内网解析
- 不使用 223.5.5.5 作触发地址：dae 对它 `must_direct`，跳过 DNS 模块

## 检查

```bash
resolvectl status
ip -4 route show default
ip -6 route show default
sudo grep -H -E '^(ROUTER|DNS|CLASSLESS_ROUTES)=' /run/systemd/netif/leases/*
curl -4 -s -o /dev/null -w '%{http_code} %{time_total}s\n' -m 8 https://<DUAL_STACK_HOST>
curl -6 -s -o /dev/null -w '%{http_code} %{time_total}s\n' -m 8 https://<DUAL_STACK_HOST>
```

预期：

- 默认 IPv4 路由网卡的 DNS 为 `1.1.1.1 8.8.8.8`，没有 IPv6 DNS server
- Lima 的 NAT 网卡可能仍列出自己的 DNS server，只要 `DNSDefaultRoute=false` 就不会作为默认解析路径
- `ip -4 route show default` 与 `ip -6 route show default` 分别确认 IPv4 与 IPv6 的默认路由来源，只对齐一边会留下绕过旁路由的出口
- `ip -6 route show default` 无输出
- lease 里 `ROUTER=` 是 DHCP option 3、`DNS=` 是 option 6，两者各自独立，网关指向旁路由不代表 DNS 也经旁路由
- 使用 DHCP option 121 时，必须把 default route 也写进 121：支持 RFC 3442 的客户端见到 121 后会按 classless routes 处理路由，121 里缺 default route 时 option 3 的默认网关不生效
- 排查境外服务慢或超时时，先对比 `curl -4` 与 `curl -6`，再看路由与 DNS；单栈正常不代表双栈正常

## 修复

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-network.yaml --tags dns
# 只处理单个节点
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-network.yaml --tags dns --limit <node>
```
