# Bypass router SNAT breaks HomeKit bridge

**日期**: 2026-07-07
**影响**: iPhone Home App 中通过 Home Assistant HomeKit Bridge 暴露的米家设备显示不可用；Home Assistant 的 zeroconf 页面仍能看到局域网设备，造成排查方向混淆。
**发现人**: 用户

## 问题

引入旁路由后，LAN 客户端的默认网关被下发为 `<BYPASS_ROUTER_IP>`。客户端访问 Home Assistant 所在的 IoT/HomeKit 网段时，也被送到旁路由。旁路由对 LAN 转发流量开启了 masquerade，导致访问 Home Assistant HomeKit Bridge 的源地址被改成 `<BYPASS_ROUTER_IP>`。

最终修复不是改 Home Assistant、Multus、HomeKit Bridge 或旁路由 NAT，而是在主路由 DHCP 中给 LAN 客户端下发到 IoT/HomeKit 网段的精确路由：

```txt
<IOT_SUBNET> via <LAN_ROUTER_IP>
```

默认网关仍保持为 `<BYPASS_ROUTER_IP>`，只有访问 IoT/HomeKit 网段时绕过旁路由。

## 现象

HomeKit Bridge 可以被发现：

```bash
dns-sd -B _hap._tcp local
```

关键输出：

```txt
_hap._tcp.  HASS Bridge <ID>
```

HomeKit Bridge 端口也能连接：

```bash
dns-sd -L "HASS Bridge <ID>" _hap._tcp local
nc -vz <HASS_BRIDGE_HOST>.local <HAP_PORT>
```

关键输出：

```txt
can be reached at <HASS_BRIDGE_HOST>.local.:<HAP_PORT>
Connection ... succeeded
```

但客户端访问 Home Assistant IoT 地址时，路由走旁路由：

```bash
route -n get <HASS_IOT_IP>
```

故障时输出：

```txt
gateway: <BYPASS_ROUTER_IP>
```

在主路由 conntrack 中可见，真实客户端 `<LAN_CLIENT_IP>` 访问 HomeKit Bridge 后，进入 IoT 网段前已经被改源为旁路由：

```bash
cat /proc/net/nf_conntrack | grep '<HASS_IOT_IP>' | grep 'dport=<HAP_PORT>'
```

故障时关键输出：

```txt
src=<BYPASS_ROUTER_IP> dst=<HASS_IOT_IP> dport=<HAP_PORT>
```

旁路由防火墙配置确认 LAN zone 开启 masquerade：

```bash
uci show firewall | grep -E "zone.*lan|masq"
```

关键事实：

```txt
firewall.<LAN_ZONE>.name='lan'
firewall.<LAN_ZONE>.masq='1'
```

## 根因

技术根因：

1. 主路由通过 DHCP 把 LAN 客户端默认网关下发为 `<BYPASS_ROUTER_IP>`。
2. 客户端没有到 `<IOT_SUBNET>` 的更精确路由，因此访问 Home Assistant IoT 地址时也走 `<BYPASS_ROUTER_IP>`。
3. 旁路由对 LAN 转发流量开启 masquerade，导致 LAN 客户端访问 `<IOT_SUBNET>` 时源地址被改成 `<BYPASS_ROUTER_IP>`。
4. DHCP 下发精确路由后，LAN 客户端到 Home Assistant IoT 地址改走 `<LAN_ROUTER_IP>`，Home App 恢复可用；本次只证明断点在“客户端到 IoT 网段的路径被送入旁路由并 SNAT”，不声称 HomeKit 协议本身必须依赖真实客户端源地址。

排查过程根因：

1. 过早把问题归因到 Home Assistant 到米家设备的出站路径，建议改 Multus/HA 路由；该方向缺少故障流量证据。
2. 过早建议改旁路由底层 nft 规则；用户需要的是最小 OpenWrt 配置层修复，不是底层实现细节。
3. 没有第一时间解释 DHCP option `121` 的含义，导致修复方案看起来像黑盒。
4. 把 `zeroconf 能看到设备` 和 `HomeKit 控制链路正常` 混在一起判断；正确做法是分别验证 mDNS 发现、HAP TCP 连接、客户端到 IoT 网段的实际路由、路由器 conntrack 源地址。

## 修复

在主路由 LAN DHCP 配置中保留默认网关为旁路由，同时下发到 IoT/HomeKit 网段的精确静态路由。

OpenWrt UCI：

```bash
uci add_list dhcp.lan.dhcp_option='121,<IOT_SUBNET>,<LAN_ROUTER_IP>'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

其中 `121` 是 DHCP Classless Static Route 选项，含义是：

```txt
目标网段 <IOT_SUBNET> 走网关 <LAN_ROUTER_IP>
```

客户端重新获取 DHCP 后，验证：

```bash
route -n get <HASS_IOT_IP>
```

修复后应从：

```txt
gateway: <BYPASS_ROUTER_IP>
```

变成：

```txt
gateway: <LAN_ROUTER_IP>
```

再次访问 HomeKit Bridge 后，在主路由 conntrack 中应看到客户端不再被旁路由改源：

```txt
src=<LAN_CLIENT_IP> dst=<HASS_IOT_IP> dport=<HAP_PORT>
```

而不是：

```txt
src=<BYPASS_ROUTER_IP> dst=<HASS_IOT_IP> dport=<HAP_PORT>
```

## 预防

- 引入旁路由作为 LAN 默认网关时，必须同时列出仍应走主路由的内网网段，并通过 DHCP option 121 下发精确路由。
- 排查 HomeKit/Bonjour/mDNS 问题时，按顺序验证：
  1. `_hap._tcp.local` 是否可发现。
  2. HAP TCP 端口是否可连。
  3. 客户端到 Home Assistant IoT 地址的实际路由。
  4. 路由器 conntrack 中源地址是否被 SNAT。
- 不能仅凭 Home Assistant zeroconf 页面能看到设备，就判断 HomeKit 控制路径正常。
- 没有抓到真实流量路径前，不要建议改 Home Assistant、Multus、Kubernetes 网络或底层 nft 规则。
- 解释 DHCP option 时必须先说明语义，再给命令；`121,<SUBNET>,<GATEWAY>` 表示“给 DHCP 客户端下发 `<SUBNET> via <GATEWAY>`”。
