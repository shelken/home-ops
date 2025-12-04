## bgp

### router-mine

```conf
# Bird 2.x 配置 - 简洁版本
router id 192.168.6.1;

log syslog { info, warning, error };

# 定义常量
define LOCAL_ASN = 64513;
define K8S_ASN = 64514;

# 设备协议
protocol device {
    scan time 10;
}

# 内核协议
protocol kernel {
    ipv4 {
        export all;
    };
    persist;
}

# 过滤器
filter service_only {
    # 只接受 /32 路由（Service IP）
    if net.len = 32 then accept;
    reject;
}

filter local_only {
    if source = RTS_STATIC then accept;
    reject;
}

# BGP 模板
template bgp k8s {
    local 192.168.6.1 as LOCAL_ASN;
    hold time 90;
    keepalive time 30;
    
    ipv4 {
        import filter service_only;
        export filter local_only;
        next hop self;
    };
}

# 创建 BGP 会话
protocol bgp sakamoto-k8s from k8s {
    neighbor 192.168.6.80 as K8S_ASN;
}

protocol bgp homelab-1 from k8s {
    neighbor 192.168.6.110 as K8S_ASN;
}
```
