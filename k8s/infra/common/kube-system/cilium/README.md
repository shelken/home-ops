## BGP Configuration

> **状态：本地站点正常**（sakamoto-k8s / homelab-1 / yuuko-k8s 与 router-mine eBGP）。
> 跨地域部分（router-home 经 ZeroTier 中继）已断开。

### router-mine (192.168.6.1)

[/etc/bird.conf](../../../../../router/mine.conf)

逐节点显式 neighbor（无网段接受），节点：sakamoto-k8s / homelab-1 / yuuko-k8s。

```mermaid
graph TD
    R_Mine[Router: Mine<br/>LAN: 192.168.6.1<br/>AS: 64513]
    Saka[Node: sakamoto-k8s<br/>192.168.6.80<br/>AS: 64514]
    H1[Node: homelab-1<br/>192.168.6.110<br/>AS: 64514]
    Yuuko[Node: yuuko-k8s<br/>192.168.6.81<br/>AS: 64514]

    R_Mine -- "eBGP (LAN)" --> Saka
    R_Mine -- "eBGP (LAN)" --> H1
    R_Mine -- "eBGP (LAN)" --> Yuuko
```

### router-home (192.168.191.10，已断开)

[/etc/bird.conf](../../../../../router/home.conf)

### Firewall Configuration

`/etc/config/firewall` (On Router-Mine)

`NOTRACK` 告诉 netfilter 不要跟踪这些包的状态，不要在 conntrack 表里创建条目，直接放行。这样它就不会因为“没看到回程包”而丢弃后续的 ACK/TLS 数据了

```conf
config rule
	option name 'Allow-K8s-LB-Asymmetric'
	option src 'lan'
	option dest 'lan'
	list proto 'all'
	option dest_ip '192.168.69.0/24'
	option target 'NOTRACK'
```

对于本地和远程站点之间的Pod CIDR（‘ 10.42.0.0/16 ‘）流量，确保在’ lan ’和‘ zt ’区域之间启用‘转发’

```bash
# Check BIRD status
birdc configure check
birdc configure
birdc show protocols
birdc show route
```
