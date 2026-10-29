# 网络配置记录

## IPv6

[HomeLab 中 K3s 的 IPv6 配置](https://yadom.in/archives/k3s-ipv6-configuration.html)

### 防火墙与 IPv6 后缀固定

所有设备获取公网 IPv6 时的后缀固定策略：

- 启用 EUI-64 生成固定后缀（`addr-gen-mode=eui64`）
- 关闭 IPv6 临时隐私扩展（`ip6-privacy=0`），避免动态变化地址干扰 DDNS 解析与防火墙放行

防火墙规则仅放行固定后缀目的地址：

目的地：`::[实际 EUI-64 后缀]/::ffff:ffff:ffff:ffff` 端口 `443`

> 注：历史 Armbian 阶段通过 nmcli 配置（`ipv6.addr-gen-mode eui64`、`ipv6.ip6-privacy 0`）；当前旁路由固件统一使用 ImmortalWrt

### NAT6

> 主路由获取公网，内部所有设备仅获取内网ipv6
>

主路由获取公网 IPv6 后，局域网下发 ULA 或通过 NAT6 进行源地址伪装，并将 `2000::/3` 默认路由指向 WAN 上游网关

### ansible k3s node-ip

```bash
#查看默认的ipv6,前缀为路由的 ula地址 ，后缀为 eui64
ansible all -m setup -a 'filter=ansible_default_ipv6'
```
