# 路由器配置文档

本目录包含主路由器 (`router-mine`) 的各项配置文档。

## 设备信息

| 项目 | 值 |
| :--- | :--- |
| **设备名称** | router-mine |
| **管理 IP** | 192.168.6.1 |
| **操作系统** | OpenWrt |
| **SSH 访问** | `ssh router-mine` |

## 配置文档

| 文档 | 说明 |
| :--- | :--- |
| [VLAN 配置](./vlan.md) | VLAN 网络划分，包括主网 (VLAN 6) 和 IoT 网 (VLAN 50) |
| [mDNS 配置](./mdns.md) | Avahi mDNS 反射，实现跨 VLAN 服务发现 |
| [BGP 配置](./bgp.md) | BIRD BGP 路由，实现跨地域 Pod 网络互通 |
| [DNS 配置](./dns.md) | dnsmasq 与 LuCI/UCI 共存、集群域分流、集群外自举记录 |

## 网络架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                     router-mine (192.168.6.1)               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  VLAN 6 (br-lan.6)          VLAN 50 (br-lan.50)            │
│  ├── 192.168.6.0/24         ├── 192.168.50.0/24            │
│  ├── 主内网                  ├── IoT 网络                   │
│  └── K8s 节点管理口          └── 智能家居设备                │
│                                                             │
│  ┌─────────────┐            ┌─────────────┐                │
│  │   Avahi     │◄──反射────►│   Avahi     │                │
│  │  (mDNS)     │            │  (mDNS)     │                │
│  └─────────────┘            └─────────────┘                │
│                                                             │
│  ┌─────────────────────────────────────────┐               │
│  │              BIRD (BGP)                  │               │
│  │  ├── 连接本地 K8s 节点 (AS 64514)        │               │
│  │  └── 连接远程路由器 via ZeroTier         │               │
│  └─────────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

## 快速命令

```bash
# 查看 VLAN 配置
cat /etc/config/network

# 查看 mDNS 服务
avahi-browse -a -t

# 查看 BGP 状态
birdc show protocols

# 查看路由表
ip route | grep 10.42
```

## 配置下发

路由器配置存放在仓库顶层 `router/`，由 `.taskfile/router.yaml` 下发：

```bash
task router:bgp:sync   # 默认入口：展示差异 → 确认 → 校验 → 整体替换 → 热加载
task router:dns:sync   # 默认入口：展示差异 → 确认 → 校验 → 下发 → 重启 dnsmasq
task router:bgp:diff   # 可选：只读检查整个 /etc/bird.conf
task router:dns:diff   # 可选：只读检查 include、专用 conf-dir 与自举 hosts
```

日常只运行对应的 `sync`；它会先自动执行同一功能的只读 `diff`，完整展示差异，再确认和
生效。可重复的首次初始化并入 `sync`，不另设 bootstrap。独立 `diff` 只用于排障、审阅
和自动检查。

BIRD 完全由 home-ops 管理，`bgp:sync` 整体同步 `/etc/bird.conf`。dnsmasq 保留 LuCI 与 UCI
手工管理，home-ops 只维护 `/etc/dnsmasq.conf` 中带标记的 include、
`/etc/dnsmasq-home-ops.d` 和 `/etc/dnsmasq.d/int.hosts`。具体机制与验证方式见
[DNS 配置](./dns.md)。

## 相关文档

- [跨地域节点互联架构](../17-add-remote-node.md) - 完整的 BGP 全互联方案（含 Cilium 配置）
