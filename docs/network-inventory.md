# 网络清单

本文件记录集群内部网络地址和 Multus 使用边界。公网域名、公网 IP 和私有服务 URL 不写入本文档。

## LoadBalancer 地址段

LB IP range: `192.168.69.0/24`

| 服务                   | IP              | 描述                      | Multus |
| ---------------------- | --------------- | ------------------------- | ------ |
| k8s-gateway            | `192.168.69.41` | 开放给外部 DNS            |        |
| envoy external gateway | `192.168.69.45` | 外部入口网关              |        |
| envoy internal gateway | `192.168.69.46` | 内部入口网关              |        |
| postgres-lb            | `192.168.69.52` | PostgreSQL LoadBalancer   |        |
| plex                   | `192.168.69.54` | Plex 服务                 |        |
| immich-db              | `192.168.69.56` | Immich 数据库             |        |
| seafile-db             | `192.168.69.57` | Seafile 数据库            |        |
| mosquitto              | `192.168.69.59` | MQTT 服务                 |        |
| victoria-logs          | `192.168.69.66` | 接收外部设备日志          |        |
| crowdsec               | `192.168.69.67` | 外部 agent / bouncer 连接 |        |

## Multus 固定地址

| 服务                 | IP              | 描述             | Multus           |
| -------------------- | --------------- | ---------------- | ---------------- |
| netbird              | `192.168.6.44`  | 已停用，保留记录 | `multus-ipv6`    |
| caddy-external       | `192.168.6.47`  | IPv6 入口与 DDNS | `multus-ipv6`    |
| home assistant       | `192.168.50.51` | IoT VLAN / mDNS  | `multus-iot`     |
| go2rtc               | `192.168.50.53` | HomeKit / mDNS   | `multus-homekit` |
| qbittorrent          | `192.168.6.58`  | IPv6 / UDP 直连  | `multus-ipv6`    |
| tailscale-sub-router | `192.168.6.65`  | IPv6 直连        | `multus-ipv6`    |
| tailscale-node-vps   | `192.168.6.66`  | IPv6 直连        | `multus-ipv6`    |

## Multus 使用边界

只有几类服务应该使用 Multus：

- `multus-ipv6`：需要 IPv6 或 UDP 直连的服务，例如 tailscale、qbittorrent、caddy-external。
- `multus-iot`：需要接入 IoT VLAN 的服务，例如 home-assistant。
- `multus-homekit`：需要 HomeKit/mDNS 特定网络路径的服务，例如 go2rtc。
- `multus-main`：保留备用。

其他需要单独 IP 的服务优先使用 LoadBalancer / L2 宣告，并严格限定暴露端口。

Multus 引用中的 IP 掩码很重要：`/32` 与 `/24` 会影响容器是否自动获得出口网段路由。

## 参考

- Multus 网络定义：[`k8s/infra/common/network/multus/networks/README.md`](../k8s/infra/common/network/multus/networks/README.md)
- 架构总览：[`docs/ARCHITECTURE.md`](./ARCHITECTURE.md)
