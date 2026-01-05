# multus 使用

## 生成 MAC

```shell
printf '02:%02X:%02X:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
```

## 用途

- 需要 IPv6 的访问时。当前集群不使用 hostnetwork，也因为一些限制不能使用IPv6，但是可以通过multus让容器单独拥有ipv6。
- 需要 mdns 的时候（智能家居的发现）

## 网络类型

| 网络名         | Master 接口 | 子网            | 用途                                                   | 使用 sbr |
| -------------- | ----------- | --------------- | ------------------------------------------------------ | -------- |
| multus-main    | eth1        | 192.168.6.0/24  | 保留备用                                               | 是       |
| multus-ipv6    | eth1        | 192.168.6.0/24  | IPv6 直连/UDP                                          | 否       |
| multus-iot     | eth1.50     | 192.168.50.0/24 | mDNS 智能家居(不关心视频流udp或者可以指定接口发送mdns) | 是       |
| multus-homekit | eth1.50     | 192.168.50.0/24 | mDNS 智能家居(无法指定接口udp)                         | 否       |

### multus-ipv6

~~使用独立的 VLAN 70 网段 (192.168.70.0/24)，避免与节点网段 (192.168.6.0/24) 冲突。~~
macvlan 无法与宿主机的父接口通信，若 Pod IP 与节点在同一网段会导致健康检查失败。

适用于需要 IPv6 直连的服务，使用细分路由绕过私网地址（不使用 sbr）：

- tailscale (subnet-router, node-vps)
- qbittorrent
- caddy-external
- netbird-router

### multus-iot

适用于需要 mDNS 发现的智能家居服务，连接到 VLAN 50 (IoT 网)：

- home-assistant (192.168.50.51)(为什么hass在50, 小米插件本地需要相同网段，为什么我在路由器配置了mdns反射，因为需要让6网段接收50网段的。但是是否可以让hass获取两个网段的ip？)
- go2rtc (192.168.50.53)（为什么go2rtc需要在50？没有理由，他也需要mdns（homekit），但是我们也有反射，可以50也可以6。但是很重要一点在于udp默认出站为默认的口，导致udp源ip最后变成node的ip，需要配置好路由保证某个请求方的ip必须是非k8s网段的。在这里也就是6网段，可以通过指定特定ip段直接eth1出去）

### multus-main

保留备用，使用 sbr (source-based routing)。

## 局限

- 使用之后，容器的网络就不再能完全被 k8s 控制，因此需要设置好路由器防火墙。至少防止外部流量随意进入。
