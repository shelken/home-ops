# DNS 设置记录

## 问题

部分节点会从 IPv6 RA/DHCPv6 获得运营商 DNS，导致解析被污染；节点 DNS 还必须经默认网关（旁路由）才能触发域名嗅探，取舍见 [ADR-0004](adr/0004-k8s-node-dns-daed-routing.md)。

## 原则

- 默认 IPv4 路由网卡显式写入 `DNS=1.1.1.1 8.8.8.8`，不使用 DHCP 下发的 DNS。
- 不修改 IP、网关、DHCP/static 模式、cloud-init 或 netplan 网络形态。
- 自动只让默认 IPv4 路由网卡参与 DNS。
- 其他网卡不参与 DNS。
- 禁止 IPv6 RA/DHCPv6 下发 DNS。

## 检查

```bash
sudo cat /etc/netplan/*.yaml
resolvectl status
```

确认结果：

```text
没有 IPv6 DNS server
IPv4 DNS 只有 1.1.1.1 和 8.8.8.8，且只来自默认 IPv4 路由网卡
```

## 日常修复

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-network.yaml --tags dns
```

DNS 策略在 `setup-network.yaml` 中统一管理（`--tags dns` 只跑 DNS 部分）。
