# DNS 设置记录

## 问题

部分节点会从 IPv6 RA/DHCPv6 获得运营商 DNS，导致解析被污染。

## 原则

- 不在 Ansible 里写死 DNS 服务器。
- 不修改 IP、网关、DHCP/static 模式、cloud-init 或 netplan 网络形态。
- 自动只让默认 IPv4 路由网卡参与 DNS。
- 其他网卡不参与 DNS。
- 禁止 IPv6 RA/DHCPv6 下发 DNS。

## 检查

```shell
sudo cat /etc/netplan/*.yaml
resolvectl status
```

确认结果：

```text
没有 IPv6 DNS server
IPv4 DNS 只来自默认 IPv4 路由网卡
```

## 日常修复

```shell
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-dns.yaml
```

`setup-dns.yaml` 只做 DNS policy，不负责网络迁移。
