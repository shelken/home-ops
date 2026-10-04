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
| [BGP 配置](./bgp.md) | BIRD BGP 路由，本地三个 K8s 节点与 router-mine 建对等（跨地域部分已断开） |
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

图中远程路由器链路（ZeroTier）已断开，当前只有本地三个 K8s 节点与 router-mine 建立 BGP。

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
task router:dns:diff   # 可选：只读检查 home-ops 专用目录
```

日常只运行对应的 `sync`；它会先自动执行同一功能的只读 `diff`，完整展示差异，再确认和
生效。独立 `diff` 只用于排障、审阅和自动检查。

BIRD 完全由 home-ops 管理，`bgp:sync` 整体同步 `/etc/bird.conf`。dnsmasq 保留 LuCI、UCI
和基础配置的手工管理，home-ops 持续同步只完整管理 `/etc/dnsmasq-home-ops.d`。具体机制
与验证方式见 [DNS 配置](./dns.md)。

## 相关文档

- [跨地域节点互联架构](../17-add-remote-node.md) - 完整的 BGP 全互联方案（含 Cilium 配置）
