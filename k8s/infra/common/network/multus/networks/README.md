# multus 使用

## 生成 MAC

```shell
printf '02:%02X:%02X:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
```

## 用途

- 需要 IPv6 的访问时。当前集群不使用 hostnetwork，也因为一些限制不能使用IPv6，但是可以通过multus让容器单独拥有ipv6。
- 需要 mdns 的时候（智能家居的发现）

## 网络类型

| 网络名 | Master 接口 | 子网 | 用途 | 使用 sbr |
|--------|-------------|------|------|----------|
| multus-ipv6 | eth1 | 192.168.6.0/24 | 需要 IPv6 直连的服务 | 否 |
| multus-iot | eth1.50 | 192.168.50.0/24 | 需要 mDNS 的智能家居服务 | 是 |
| multus-main | eth1 | 192.168.6.0/24 | 保留备用 | 是 |

### multus-ipv6

适用于需要 IPv6 直连的服务，使用细分路由绕过私网地址（不使用 sbr）：
- tailscale (subnet-router, node-vps)
- qbittorrent
- caddy-external
- netbird-router

### multus-iot

适用于需要 mDNS 发现的智能家居服务，连接到 VLAN 50 (IoT 网)：
- home-assistant (192.168.50.51)
- go2rtc (192.168.6.53)

### multus-main

保留备用，使用 sbr (source-based routing)。

## 局限

- 使用之后，容器的网络就不再能完全被 k8s 控制，因此需要设置好路由器防火墙。至少防止外部流量随意进入。
