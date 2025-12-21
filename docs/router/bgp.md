# BGP 路由配置 (BIRD)

本文档记录了主路由器 (`router-mine`) 和远程路由器 (`router-home`) 的 BGP 配置，用于实现跨地域 Pod 网络互通。

## 概述

通过在两端路由器上运行 BIRD BGP 协议，打通跨地域的 Pod 网络：

- **本地网络 (Mine)**: `192.168.6.0/24`
- **远程网络 (Home)**: `192.168.0.0/24`
- **互联链路 (VPN)**: ZeroTier `192.168.191.0/24`
- **Pod 网络**: `10.42.0.0/16` (Native Routing)

## 架构拓扑

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│         Local Site (Mine)           │     │        Remote Site (Home)           │
│                                     │     │                                     │
│  ┌──────────────┐  ┌─────────────┐  │     │  ┌─────────────┐  ┌──────────────┐  │
│  │ sakamoto-k8s │  │ other nodes │  │     │  │  yuuko-k8s  │  │              │  │
│  │ 192.168.6.80 │  │             │  │     │  │ 192.168.0.81│  │              │  │
│  │   AS 64514   │  │   AS 64514  │  │     │  │   AS 64514  │  │              │  │
│  └──────┬───────┘  └──────┬──────┘  │     │  └──────┬──────┘  └──────────────┘  │
│         │iBGP             │iBGP     │     │         │eBGP                       │
│         ▼                 ▼         │     │         ▼                           │
│  ┌──────────────────────────────┐   │     │  ┌──────────────────────────────┐   │
│  │       router-mine            │   │     │  │       router-home            │   │
│  │  LAN: 192.168.6.1            │◄──┼─────┼──│  LAN: 192.168.0.1            │   │
│  │  ZT:  192.168.191.12         │   │eBGP │  │  ZT:  192.168.191.10         │   │
│  │  AS:  64513                  │   │     │  │  AS:  64515                  │   │
│  └──────────────────────────────┘   │     │  └──────────────────────────────┘   │
└─────────────────────────────────────┘     └─────────────────────────────────────┘
```

## ASN 分配

| 设备 | ASN | 角色 |
| :--- | :--- | :--- |
| **router-mine** | 64513 | 本地核心网关 |
| **router-home** | 64515 | 远程中继网关 |
| **Cilium (所有节点)** | 64514 | K8s Pod 网络 |

## 安装

```bash
opkg update
opkg install bird2
```

## 配置文件

### router-mine (本地路由器)

**路径**: `/etc/bird.conf`

```bird
router id 192.168.6.1;

define LOCAL_ASN = 64513;
define K8S_ASN = 64514;

protocol device {
    scan time 10;
}

protocol kernel {
    ipv4 {
        import none;
        export all;
    };
}

protocol direct {
    ipv4;
    interface "br-lan*", "zt*";
}

# K8s 节点模板
template bgp k8s {
    local as LOCAL_ASN;
    ipv4 {
        import all;
        export all;
        next hop self;
    };
}

# 路由器互联模板
template bgp router_peer {
    local as LOCAL_ASN;
    ipv4 {
        import all;
        export all;
        next hop self;
    };
}

# 连接本地节点 (Sakamoto)
protocol bgp sakamoto_k8s from k8s {
    neighbor 192.168.6.80 as K8S_ASN;
}

# 连接远程路由器 (Router-Home) via ZeroTier
protocol bgp router_home from router_peer {
    neighbor 192.168.191.10 as 64515;
}
```

### router-home (远程路由器)

**路径**: `/etc/bird.conf`

```bird
router id 192.168.191.10;

define LOCAL_ASN = 64515;
define K8S_ASN = 64514;

protocol device {
    scan time 10;
}

protocol kernel {
    ipv4 {
        import none;
        export all;
    };
}

protocol direct {
    ipv4;
    interface "br-lan*", "zt*";
}

# K8s 节点模板
template bgp k8s_peer {
    local as LOCAL_ASN;
    ipv4 {
        import all;
        export all;
        next hop self;
    };
}

# 路由器互联模板
template bgp router_peer {
    local as LOCAL_ASN;
    ipv4 {
        import all;
        export all;
        next hop self;
    };
}

# 连接本地节点 (Yuuko)
protocol bgp yuuko from k8s_peer {
    neighbor 192.168.0.81 as K8S_ASN;
}

# 连接本地路由器 (Router-Mine) via ZeroTier
protocol bgp router_mine from router_peer {
    neighbor 192.168.191.12 as 64513;
}
```

## 服务管理

```bash
# 启动服务
/etc/init.d/bird start

# 停止服务
/etc/init.d/bird stop

# 重启服务
/etc/init.d/bird restart

# 查看状态
/etc/init.d/bird status

# 开机自启
/etc/init.d/bird enable
```

## 验证

### 查看 BGP 邻居状态

```bash
birdc show protocols
```

### 查看路由表

```bash
# 查看所有 BGP 学习到的路由
birdc show route

# 查看 Pod 网段路由
ip route | grep 10.42
```

### 预期结果

**router-mine** 上应看到:
```
10.42.3.0/24 via 192.168.191.10 ...  # 远程 Pod 网段
```

**router-home** 上应看到:
```
10.42.0.0/24 via 192.168.191.12 ...  # 本地 Pod 网段
10.42.1.0/24 via 192.168.191.12 ...
```

## Cilium 配置

K8s 侧的 BGP 配置请参考：[跨地域节点互联架构](../17-add-remote-node.md)

## 相关文档

- [VLAN 配置](./vlan.md) - VLAN 网络划分
- [mDNS 配置](./mdns.md) - 跨 VLAN 的 mDNS 反射配置
- [跨地域节点互联](../17-add-remote-node.md) - 完整的 BGP 全互联方案