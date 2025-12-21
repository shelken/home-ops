# mDNS 跨网段配置 (Avahi)

本文档记录了主路由器 (`router-mine`) 的 mDNS 反射配置，用于实现跨 VLAN 的服务发现。

## 概述

通过 Avahi 的 reflector 功能，将 mDNS 广播在 VLAN 6 (主网) 和 VLAN 50 (IoT 网) 之间转发，使得：

- 主网设备可以发现 IoT 网段的 Home Assistant
- Apple 设备可以通过 HomeKit 连接 IoT 网段的智能家居桥接器

## 安装

```bash
opkg update
opkg install avahi-nodbus-daemon avahi-utils
```

## 配置文件

**路径**: `/etc/avahi/avahi-daemon.conf`

```ini
[server]
check-response-ttl=yes
use-ipv4=yes
use-ipv6=no
allow-interfaces=br-lan.6,br-lan.50
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[publish]
publish-hinfo=no
publish-workstation=no

[reflector]
enable-reflector=yes
reflect-ipv=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
```

### 关键配置说明

| 配置项 | 值 | 说明 |
| :--- | :--- | :--- |
| `allow-interfaces` | `br-lan.6,br-lan.50` | 只在这两个 VLAN 接口上监听和广播 |
| `enable-reflector` | `yes` | 启用 mDNS 反射，跨接口转发服务发现 |
| `reflect-ipv` | `no` | 不修改反射记录的 IP 版本 |
| `check-response-ttl` | `yes` | 检查响应 TTL，减少跨网段设备名冲突 |

## 服务管理

```bash
# 启动服务
/etc/init.d/avahi-daemon start

# 停止服务
/etc/init.d/avahi-daemon stop

# 重启服务
/etc/init.d/avahi-daemon restart

# 查看状态
/etc/init.d/avahi-daemon status

# 开机自启
/etc/init.d/avahi-daemon enable
```

## 验证

### 查看所有 mDNS 服务

```bash
# 查看 VLAN 6 的服务
avahi-browse -a -t 2>/dev/null | grep 'br-lan.6'

# 查看 VLAN 50 的服务
avahi-browse -a -t 2>/dev/null | grep 'br-lan.50'
```

### 查看服务详情（含 IP）

```bash
# 查看 Home Assistant 相关服务
avahi-browse -a -t -r 2>/dev/null | grep -A5 'HASS'

# 查看所有服务的 IP
avahi-browse -a -t -r -p 2>/dev/null | awk -F';' '/=;/ {print $4, $7, $8}'
```

### 解析主机名

```bash
avahi-resolve -n <hostname>.local
```

## 客户端测试

### macOS

```bash
# 浏览 HomeKit 设备
dns-sd -B _hap._tcp local.

# 查询具体服务
dns-sd -L "HASS Bridge F76928" _hap._tcp local.

# 解析主机名到 IP
dns-sd -G v4 <hostname>.local
```

## 常见问题

### 设备名被自动改成 xxx-2

**原因**: 跨网段切换时 mDNS 冲突，设备自动重命名。

**解决**:
1. 确保 `check-response-ttl=yes` 已配置
2. 重启 avahi: `/etc/init.d/avahi-daemon restart`
3. 在设备上重新设置主机名

macOS 修复命令：
```bash
sudo scutil --set ComputerName "your-name"
sudo scutil --set LocalHostName "your-name"
sudo killall -9 mDNSResponder
```

## 相关文档

- [VLAN 配置](./vlan.md) - VLAN 网络划分
- [BGP 配置](./bgp.md) - BGP 路由配置