## ipv6

[HomeLab 中 K3s 的 IPv6 配置](https://yadom.in/archives/k3s-ipv6-configuration.html)

### 防火墙与ipv6后缀的固定

> 此配置为所有设备获取公网ipv6时配置

tvbox 关闭隐私ipv6与启用 eui-64 地址：

addr-gen-mode=eui64 意味着接收的ipv6后缀为固定的mac生成的。
关闭 ip6-privacy 意味着不再使用一个动态的v6地址来发起请求，则eth0接口有且仅有一个v6地址，这方便我们ddns和防火墙配置。

```shell
nmcli connection modify "Armbian ethernet" ipv6.addr-gen-mode eui64
nmcli connection modify "Armbian ethernet" ipv6.ip6-privacy 0
nmcli connection reload
nmcli connection up "Armbian ethernet"
```

防火墙配置仅允许该后缀

目的地：`::[实际eui64地址]/::ffff:ffff:ffff:ffff` 端口 443

### NAT6

> 主路由获取公网，内部所有设备仅获取内网ipv6
>

路由器主要两点：配置路由，将`2000::/3`的出网指向拥有ipv6的接口上，并且要指定gateway就是上游的gateway链路地址，但是这个可以变化的，因此

使用插件nat6助手更好点。然后第二点是配置经过wan接口的所有出网流量进行源伪装，即把源所有替换为路由器公网的v6 ip


### ansible k3s node-ip

```shell
#查看默认的ipv6,前缀为路由的 ula地址 ，后缀为 eui64
ansible all -m setup -a 'filter=ansible_default_ipv6'
```

