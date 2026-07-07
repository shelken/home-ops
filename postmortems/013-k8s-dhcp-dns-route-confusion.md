# K8s DHCP DNS route confusion

**日期**: 2026-07-07
**影响**: K8s 节点外连与 Flux OCI 拉取间歇失败；排查过程中多次把默认路由、DHCP DNS、CoreDNS 上游和 registry mirror 混为一谈，产生无效方案与重复验证。
**发现人**: 用户

## 问题

K8s 节点的默认路由已经按 DHCP 指向旁路由，但节点 DNS 仍可能来自主路由。CoreDNS 配置为 `forward . /etc/resolv.conf`，因此会继承宿主机 systemd-resolved 的上游 DNS。

排查时错误地把“公网默认路由走旁路由”理解成“DNS 也一定走旁路由”，导致对 Flux `OCIRepository` 拉取失败的原因判断反复偏移。

## 现象

最小复现命令：

```bash
# 节点上分别检查路由与 DNS 来源
ip -4 route get <PUBLIC_IP>
ip -4 route get <LAN_DNS_IP>
cat /run/systemd/resolve/resolv.conf
sudo grep -H -E '^(ROUTER|DNS|CLASSLESS_ROUTES)=' /run/systemd/netif/leases/*

# 集群内检查 CoreDNS 解析结果
kubectl -n flux-system exec deploy/source-controller -- \
  nslookup <OCI_REGISTRY_DOMAIN> <COREDNS_SERVICE_IP>

# 对比不同 DNS 上游
 dig +short A <OCI_REGISTRY_DOMAIN> @<LAN_ROUTER_IP>
 dig +short A <OCI_REGISTRY_DOMAIN> @<BYPASS_ROUTER_IP>
```

关键现象：

```txt
ip route get <PUBLIC_IP>       -> via <BYPASS_ROUTER_IP>
/run/systemd/resolve/resolv.conf -> nameserver <LAN_ROUTER_IP> 或 <BYPASS_ROUTER_IP>
DHCP lease ROUTER              -> <BYPASS_ROUTER_IP>
DHCP lease DNS                 -> 取决于 DHCP option 6
DHCP lease CLASSLESS_ROUTES    -> 必须包含 default route，否则支持 RFC3442 的客户端会忽略 option 3
```

Flux 告警表现：

```txt
FluxOCIRepositoryOciartifactpullfailed
message="failed to determine artifact digest: Get \"https://<OCI_REGISTRY>/v2/\": TLS handshake timeout / EOF"
```

## 根因

错误假设：

- 以为 DHCP option 3 指向旁路由后，客户端 DNS 会自动使用旁路由。
- 以为 CoreDNS `forward . /etc/resolv.conf` 只跟默认路由有关。
- 以为 `registries.yaml` 的 containerd mirror 会影响 Flux `source-controller` 的 `OCIRepository` 拉取。
- 以为修 node netplan 就能修所有 OCI 拉取失败。
- 以为 `dhcp4: true` 就足以表达最终网络状态，忽略了 DHCP option 6 和 option 121 的实际内容。

实际约束：

- DHCP option 3 只控制 router/default gateway；DHCP option 6 才控制 DNS server。
- OpenWrt/dnsmasq 未显式配置 option 6 时，可能默认下发路由器自身作为 DNS。
- DHCP option 121 存在时，支持 RFC3442 的客户端会按 classless routes 处理路由；如果 121 没包含 default route，option 3 的默认网关不会按预期生效。
- CoreDNS `forward . /etc/resolv.conf` 继承的是 CoreDNS Pod/宿主机解析链路，不是直接继承“默认路由下一跳”。
- Flux `source-controller` 拉 `OCIRepository` 使用自己的 HTTP/OCI 客户端，不等同于 kubelet/containerd 拉镜像；`/etc/rancher/k3s/registries.yaml` 不能解释 `OCIRepository` 对外访问的 DNS 结果。

缺失检查点：

- 没有先同时检查 `ROUTER=`、`DNS=`、`CLASSLESS_ROUTES=`。
- 没有先对比 `<OCI_REGISTRY_DOMAIN>` 在 `<LAN_ROUTER_IP>` 与 `<BYPASS_ROUTER_IP>` 下的解析结果。
- 没有先确认 `source-controller` 所在节点、Pod DNS 和 CoreDNS 上游。
- 在方案设计里过早引入 host_vars、MAC match、独立 playbook、静态 route 等不必要结构。

## 修复

最终收敛方式：

- 路由器 DHCP 负责下发真实网络意图：
  - option 3 指向旁路由。
  - option 6 显式下发旁路由 DNS。
  - option 121 包含 default route 和特殊网段路由。
- Ansible 只负责让 K8s 节点本地状态一致：
  - cloud-init 不管理网络。
  - K8s LAN 网卡使用 DHCP。
  - 清理旧 netplan 残留。
  - DNS policy 只允许默认 IPv4 路由网卡参与 DNS，拒绝 IPv6 DNS。
- `setup-dns.yaml` 保留单入口：先归一化 K8s 节点 LAN，再复用 `dns-patch.yaml` 做 DNS policy。
- `dns-patch.yaml` 精简为 systemd-networkd/netplan 的最小逻辑，不再保留 NetworkManager 和全局 DNS 清理分支。

验证命令：

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-dns.yaml
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/setup-dns.yaml

for host in <K8S_NODE_IPS>; do
  ssh "$host" '
    ip -4 route show default
    grep -E "^nameserver" /run/systemd/resolve/resolv.conf
    sudo grep -H -E "^(ROUTER|DNS|CLASSLESS_ROUTES)=" /run/systemd/netif/leases/*
  '
done

kubectl get ocirepository -A
kubectl -n flux-system exec deploy/source-controller -- \
  nslookup <OCI_REGISTRY_DOMAIN> <COREDNS_SERVICE_IP>
```

## 预防

- 排查网络时必须分开看：route、DNS、DHCP lease、CoreDNS、应用访问；不准用“默认网关正确”推断“DNS 正确”。
- DHCP 相关问题必须先看 lease：`ROUTER=`、`DNS=`、`CLASSLESS_ROUTES=`。
- 使用 DHCP option 121 时，必须把 default route 也写进 121；不要只依赖 option 3。
- CoreDNS 使用 `/etc/resolv.conf` 时，必须验证宿主机最终 `nameserver`，而不是只看路由表。
- Flux `OCIRepository` 失败时，先查 `source-controller` 日志和 DNS 解析；不要用 containerd `registries.yaml` 解释 Flux OCI 拉取路径。
- Ansible 网络修复优先最小化：少文件、少变量、不引入 MAC match 或静态路由，除非现场证据证明必须。
