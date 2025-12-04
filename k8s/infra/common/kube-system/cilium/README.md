## bgp

### router-mine

`/ect/bird.conf`

```conf
router id 192.168.6.1;

log syslog { info, warning, error };

# 定义常量
define LOCAL_ASN = 64513;
define K8S_ASN = 64514;

# 设备协议 - 正确
protocol device {
    scan time 10;
}

# 直连协议 - 新增
protocol direct {
    ipv4;
    # 指定您的接口，通常是 br-lan（LAN网桥）
    interface "br-lan";
}

# 内核协议 - 修正
protocol kernel {
    ipv4 {
        import all;      # 从内核学习路由
        export all;      # 导出路由到内核路由表
    };
    persist;
    learn;               # 学习直接路由
}

# 过滤器 - 修正
filter accept_k8s_routes {
    # 只接受 Kubernetes 的服务 IP（/32）
    if net.len = 32 then accept;
    
    # 可选：也接受 Pod CIDR（10.42.0.0/16）
    # if net = 10.42.0.0/16 then accept;
    
    reject;
}

filter export_local_routes {
    # 导出本地网络和直连路由
    #if net = 192.168.6.0/24 then accept;    # LAN 网络
    #if source = RTS_DEVICE then accept;     # 直连路由
    #if source = RTS_STATIC then accept;     # 静态路由
    reject;
}

# BGP 模板 - 修正
template bgp k8s {
    local as LOCAL_ASN;            # 正确的语法
    hold time 90;
    keepalive time 30;
    
    ipv4 {
        import filter accept_k8s_routes;
        export filter export_local_routes;
        next hop self;            # 确保下一跳设置正确
    };
}

# 创建 BGP 会话 - 修正
protocol bgp sakamoto_k8s from k8s {
    neighbor 192.168.6.80 as K8S_ASN;
}

protocol bgp homelab_1 from k8s {
    neighbor 192.168.6.110 as K8S_ASN;
}
```

`NOTRACK` 告诉 netfilter 不要跟踪这些包的状态，不要在 conntrack 表里创建条目，直接放行。这样它就不会因为“没看到回程包”而丢弃后续的 ACK/TLS 数据了

`/etc/config/firewall`

```conf
config rule
	option name 'Allow-K8s-LB-Asymmetric'
	option src 'lan'
	option dest 'lan'
	list proto 'all'
	option dest_ip '192.168.69.0/24'
	option target 'NOTRACK'
```
