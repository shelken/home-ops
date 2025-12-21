# VLAN 网络配置

本文档记录了主路由器 (`router-mine`) 的 VLAN 网络划分配置。

## 概述

路由器使用 DSA (Distributed Switch Architecture) 配置 VLAN，通过 `bridge-vlan` 方式在主网桥 `br-lan` 上划分多个虚拟网络。

## VLAN 定义

| VLAN ID | 接口名称 | 逻辑接口    | 子网              | 网关         | 用途                                                 |
| :------ | :------- | :---------- | :---------------- | :----------- | :--------------------------------------------------- |
| **6**   | lan      | `br-lan.6`  | `192.168.6.0/24`  | 192.168.6.1  | **主内网**：家庭设备、K8s 节点管理口                 |
| **50**  | viot     | `br-lan.50` | `192.168.50.0/24` | 192.168.50.1 | **IoT 网络**：智能家居设备，通过 Multus CNI 接入 K8s |

## 物理端口配置

所有 LAN 口均配置为混合模式，同时承载主网和 IoT 网络流量：

| 物理端口 | VLAN 6 (Main)  | VLAN 50 (IoT) | 说明           |
| :------- | :------------- | :------------ | :------------- |
| **lan1** | Untagged (u\*) | Tagged (t)    | PVE / K8s 节点 |
| **lan2** | Untagged (u\*) | Tagged (t)    | PVE / K8s 节点 |
| **lan3** | Untagged (u\*) | Tagged (t)    | PVE / K8s 节点 |

### 标签说明

- **Untagged (u\*)**: 未打标签的帧进入 VLAN 6。普通设备直连网口会自动获取 `192.168.6.x` IP
- **Tagged (t)**: 只有带 VLAN 50 标签的帧才会被处理。K8s 节点通过 `eth1.50` 子接口接入

## 配置文件

**路径**: `/etc/config/network`

```config
# 主网接口
config interface 'lan'
	option device 'br-lan.6'
	option ipaddr '192.168.6.1'
	option netmask '255.255.255.0'

# IoT 接口
config interface 'viot'
	option device 'br-lan.50'
	option ipaddr '192.168.50.1'
	option netmask '255.255.255.0'

# VLAN 6 端口配置
config bridge-vlan
	option device 'br-lan'
	option vlan '6'
	list ports 'lan1:u*'
	list ports 'lan2:u*'
	list ports 'lan3:u*'

# VLAN 50 端口配置
config bridge-vlan
	option device 'br-lan'
	option vlan '50'
	list ports 'lan1:t'
	list ports 'lan2:t'
	list ports 'lan3:t'
```

## 相关文档

- [mDNS 配置](./mdns.md) - 跨 VLAN 的 mDNS 反射配置
- [BGP 配置](./bgp.md) - BGP 路由配置
