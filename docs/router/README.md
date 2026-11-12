# 路由器配置文档

本目录包含主路由器 (`router-mine`) 的各项配置文档

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
| [mDNS 配置](./mdns.md) | Avahi mDNS 反射，实现跨 VLAN 服务发现，由 nix-config 声明 |
| [BGP 配置](./bgp.md) | BIRD BGP 路由，本地三个 K8s 节点与 router-mine 建对等（跨地域部分已断开），由 nix-config 声明 |
| [DNS 配置](./dns.md) | 集群域分流与集群外自举记录，由 nix-config 声明 |

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

图中远程路由器链路（ZeroTier）已断开，当前由本地三个 K8s 节点与 router-mine 建立 BGP

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

主路由 router-mine 的配置整体由 nix-config 的 `hosts/router-mine/` 声明并下发（DNS、DHCP、防火墙、BIRD、Avahi 等），home-ops 不再下发。旁路由 dae 存放在仓库顶层 `router/`，由 `.taskfile/router.yaml` 下发：

```bash
task router:dae:sync   # 默认入口：旁路由 dae 二进制、init 脚本、配置与服务状态
task router:dae:diff   # 可选：只读检查旁路由 dae；配置中的链接已脱敏
```

日常运行 `sync`，会自动执行只读 `diff` 展示差异，再确认生效。独立 `diff` 用于排障、审阅与自动化巡检

BIRD、Avahi、dnsmasq 的配置由 nix-config 声明，见 [ADR-0010](../adr/0010-router-bird-avahi-declared-in-nix-config.md) 与 [DNS 配置](./dns.md)

各功能在 `router/<功能>/spec.py` 声明受管文件、校验、生效与验证命令，由 `router/declare.py` 统一执行 diff 与 sync：先在远端暂存目录校验全部候选文件，再原子替换有变化的文件

旁路由 dae 的选型与回滚见 [ADR-0007](../adr/0007-bypass-router-dae-declarative.md)。配置在 `router/dae/config.sops.dae`，用 `sops router/dae/config.sops.dae` 直接编辑 dae 原文。期望状态为 daed 停止并禁用、dae 启用并运行，首次 sync 即完成切换，会短暂中断所有经旁路由的出网流量

dae 没有 Web UI，切换节点与修改规则需修改仓库后 sync。dae 默认不自动刷新订阅，由 `router/dae/dae.init` 的独立 procd 实例每 6 小时执行一次 `hot_reload`。dae 二进制与 init 脚本由 sync 下发，opkg 升级如果覆盖文件，会在下一次 sync 时自动恢复

dae 配置包含订阅与节点凭据。`declare.py` 对标记为 `sensitive` 的文件执行脱敏，diff 和报错中的 `scheme://...` 链接统一替换为 `scheme://<已隐藏#哈希>`。Agent 仅使用 `task router:dae:diff` 审查变更，禁止读取或解密敏感配置

## 相关文档

- [跨地域节点互联架构（历史）](../17-add-remote-node.md)：完整的 BGP 全互联方案（含 Cilium 配置）
