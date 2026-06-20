# TVBox 旁路由分担主路由流量

## 需求转变过程

最初想把 TVBox 当主路由用，单网口作为 LAN。发现 TVBox 缺 USB WAN 驱动，单网口做主路由不如原主路由稳。改为 TVBox 做旁路由，分担插件。

## 主路由 vs TVBox 硬件数据

| 项 | router-mine | TVBox |
|---|---|---:|
| 架构 | MT7621 / MIPS 1004Kc | S905X3 / ARMv8 |
| 内存 | 256MB（可用约 72MB，有 swap） | 3.7GB（可用 3.56GB，无 swap） |
| Load | 0.5~0.9 | 0.00 |
| conntrack | 约 1100 | 约 1 |
| CPU 特性 | 无 AES/SHA 指令 | aes sha1 sha2 crc32 |

## ImmortalWrt-ImageBuilder 单网口设备的默认网络行为

[ImmortalWrt-ImageBuilder](https://github.com/shelken/ImmortalWrt-ImageBuilder) 的 `files/etc/uci-defaults/99-custom.sh` 根据网口数量决定网络配置。基于 [wukongdaily/AutoBuildImmortalWrt](https://github.com/wukongdaily/AutoBuildImmortalWrt) 修改。

**多网口（2 个及以上）：**

- 第一个网口为 WAN（DHCP 客户端）
- 其余网口桥接为 LAN
- LAN 固定 192.168.100.1，开启 DHCP server

**单网口：**

- 唯一网口整体作为 DHCP 客户端
- 不分配固定 IP，去上级路由器查 IP
- 不给下游分配 IP
- Wi-Fi 桥接在同一个 br-lan 上，也不分配 IP

项目 README 和 release box.md 明确写了单网口设备默认 DHCP 模式，不是 bug。

## 我的配置选择

## daed 专项配置

daed 相关内容已拆到 [23-daed-on-tvbox.md](23-daed-on-tvbox.md)：

- BTF 内核选择
- Hysteria2 no-obfs 兼容性
- DNS 与 routing 规则
- DNS 上游建议
- 健康检查与 IPv6


最初需求是单网口做 LAN，固定 IP，开 DHCP server，直连管理。项目默认把单网口当 DHCP 客户端。场景不同，我改了配置。

修改位置：`files/etc/uci-defaults/99-custom.sh` 的单网口分支。

```sh
if [ "$count" -eq 1 ]; then
    uci set network.lan.device='br-lan'
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$router_ip"
    uci set network.lan.netmask='255.255.255.0'
    uci set dhcp.lan.dhcpv4='server'
    uci delete dhcp.lan.ignore 2>/dev/null
    uci commit network
    uci commit dhcp
```

不改 WAN/WAN6，不禁用。

IP 来源：默认 192.168.100.1。也可以用 Workflow UI 自定义（写入 `/etc/config/custom_router_ip.txt`）。

## 每次升级后网络不通的原因

升级用 restore 会恢复旧 network 配置。项目默认单网口是 DHCP 客户端，所以 `network.lan.proto` 会被覆盖回 dhcp。再刷一次，在升级命令里选择恢复配置，它又把旧的 LAN 配置带回来了。

和 dnsmasq 无关。

## 构建固件会漏掉的 USB 驱动

`n1/build.sh` 默认 PACKAGES 不包含 USB modem 驱动。随身 Wi-Fi / 4G 模块（F50）插上后不会被识别。

需要的包：

```text
usb-modeswitch
uqmi umbim wwan
luci-proto-3g luci-proto-ncm luci-proto-qmi luci-proto-mbim
kmod-usb-net
kmod-usb-net-cdc-ether
kmod-usb-net-rndis
kmod-usb-net-cdc-ncm
kmod-usb-net-qmi-wwan
kmod-usb-net-cdc-mbim
kmod-usb-serial-option
kmod-usb-serial-wwan
```

ophub 官方 ImageBuilder 的默认包列表里这些驱动已经带了。

## 升级命令

脚本在 `scripts/update-tvbox.sh`。

```bash
scripts/update-tvbox.sh ~/Downloads/固件.img.gz
```

跨大版本（25.x → 24.10，涉及 apk 和 opkg 切换）时不保留配置。

## 升级后网络不通的恢复

HDMI 接 TVBox 直接输：

```sh
uci set network.lan.proto=static
uci set network.lan.ipaddr=192.168.100.1
uci set network.lan.netmask=255.255.255.0
uci commit network
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
```

还连不上就绕过 UCI：

```sh
ip addr flush dev eth0
ip addr add 192.168.100.1/24 dev eth0
ip link set eth0 up
```

电脑手动设 IP 192.168.100.2，访问 192.168.100.1。

## 通信规则迁移

旁路由模式下，客户端流量路径是：

```text
客户端 → TVBox → router-mine → 公网
```

留在 router-mine：公网入站、端口转发、VLAN 隔离。

搬到 TVBox：由 TVBox 承载的插件产生的规则。旁路由不会挡住公网入站，因为公网入站先到 router-mine WAN，不经过 TVBox。

## 旁路由防火墙

TVBox 必须放行经过它的流量，否则客户端会断：

```text
LAN → LAN
LAN → WAN/Internet
masq/NAT 开启
```

## 主路由 IPv6 RA relay 下发的 DNS 会绕过 TVBox/daed

旁路由模型依赖客户端 DNS 走 TVBox 转发路径，再经 daed 处理。如果客户端同时从主路由 RA relay 收到运营商 IPv6 DNS，macOS 等系统可能优先使用 IPv6 DNS，链路变为：

```text
Client → 上游 IPv6 DNS:53 → 主路由 IPv6 relay → 公网
```

这条路径不经过 TVBox，DNS 不会进入 daed DNS routing，实际解析返回污染结果。

确认主路由能否安全改 RA server 的前提：检查是否从 WAN6 获得 delegated prefix。

```sh
ifstatus wan6
```

如果 `ipv6-prefix=[]` 且 `delegation=false`，则不能直接把 LAN RA 从 relay 改成 server，否则客户端失去 IPv6。

当前止血方案：保留 RA relay，阻断 LAN 到 WAN 的 IPv6 DNS 53 端口，让客户端回退到 DHCPv4 下发的 IPv4 DNS（由主路由 DHCP option 6 设定）。

```sh
uci add firewall rule
uci set firewall.@rule[-1].name='Block-LAN-IPv6-DNS'
uci set firewall.@rule[-1].family='ipv6'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].target='REJECT'
uci commit firewall
/etc/init.d/firewall restart
```

验证：

```sh
dig @<RA_RDNSS_IPV6> www.google.com A
# 期望：connection timed out; no servers could be reached

dig www.google.com A
# 期望：SERVER 是 DHCPv4 IP，返回正常地址
```

这条规则只拦 LAN → WAN 方向的 IPv6 DNS，不关闭 IPv6 地址、默认路由或其他 IPv6 流量。

## DHCP 下发旁路由网关的自环风险

旁路由给客户端当默认网关，但旁路由自己的上游默认网关仍然必须是主路由：

```text
客户端 → TVBox → router-mine → 公网
TVBox default route → router-mine
```

如果 TVBox 的 LAN 仍是 DHCP client，主路由下发：

```text
3,<TVBOX_IP>
6,<TVBOX_IP>
```

TVBox 自己也会吃到 DHCP option 3，默认路由变成：

```text
default via <TVBOX_IP>
```

这会形成路由自环，表现为 TVBox 出不了网、daed reload 卡在等待网络、客户端全部断网。

因此切换全网网关前，先把 TVBox LAN 固定为静态地址，并明确上游网关：

```sh
uci set network.lan.proto='static'
uci set network.lan.ipaddr='<TVBOX_IP>'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='<MAIN_ROUTER_IP>'
uci set network.lan.peerdns='0'
uci add_list network.lan.dns='223.5.5.5'
uci commit network
/etc/init.d/network restart
```

验证：

```sh
ip route
# 期望：default via <MAIN_ROUTER_IP> dev br-lan
```

迁移时更稳的顺序：先只下发 DNS option `6,<TVBOX_IP>`；确认 DNS 和 daed 稳定后，再考虑下发默认网关 option `3,<TVBOX_IP>`。
