# 跨网段（异地）节点加入集群的网络配置指南

本文档记录了将异地节点（如通过 ZeroTier/Tailscale 连接的远程节点）加入本地 K3s 集群时，解决 CNI (Cilium) 互通与监控 (`kubectl top node`) 问题的完整排查过程与最终方案。

## 背景与问题

**场景**：
- **主集群**：位于本地局域网 `192.168.6.x`。
- **远程节点**：`yuuko-k8s` (`192.168.0.81`)，通过 ZeroTier 连接到主集群所在的路由器。
- **连接方式**：路由器作为网关，运行 ZeroTier (`192.168.191.x`) 并运行 BIRD (BGP) 进行路由分发。
- **CNI**：Cilium 使用 Native Routing (BGP) 模式。

**症状**：
1. `kubectl top node` 无法获取远程节点数据（Metrics Server 无法连接 Kubelet）。
2. 远程节点上的 Pod 无法与主集群 Pod 互通。
3. Router 上的 BGP 会话一直处于 `Active (Socket: Connection refused)` 或 `Connect` 状态。

## 根因分析

1. **路由模式不匹配**：
   - 初始 Cilium 配置开启了 `autoDirectNodeRoutes: true`，这要求所有节点在同一 L2 网段。跨网段节点无法通过此机制学习路由。
   - **解决**：改用 BGP 动态路由交换。

2. **BGP 连接被拒绝 (Connection Refused)**：
   - Cilium 默认配置 **不监听 179 端口**，只作为客户端主动连接。
   - 路由器尝试主动连接远程节点时，因 Cilium 未监听端口而被拒绝 (RST)。

3. **源地址不匹配 (Source IP Mismatch)**：
   - **NAT 干扰**：路由器通过 ZeroTier 接口发包时，防火墙的 Masquerade 规则将源 IP 修改为 ZeroTier IP (`192.168.191.12`)，而 Cilium 期待的 Peer 是 LAN IP (`192.168.6.1`)，导致握手失败或被拒绝。
   - **自动选路行为**：远程节点 Cilium 主动连接路由器时，操作系统自动选择 ZeroTier 接口 IP (`192.168.191.10`) 作为源 IP。路由器的 BIRD 配置仅指定了 neighbor 为 `192.168.0.81`，因此拒绝了来自“未知 IP” `192.168.191.10` 的连接。

## 解决方案

### 1. Cilium 配置 (`networks.yaml`)

修改 `CiliumBGPClusterConfig`，采用 **双 Peer 策略** 以兼容本地和远程节点。

- **Peer 1**: `192.168.6.1` (原有，供本地节点使用)。
- **Peer 2**: `192.168.191.12` (路由器的 ZeroTier IP，供远程节点使用)。

这样，远程节点可以通过最优路径（ZeroTier 直连）连接路由器，避免了 NAT 对源 IP 的干扰。

```yaml
spec:
  bgpInstances:
    - name: cilium
      localASN: 64514
      peers:
        - name: router-mine
          peerASN: 64513
          peerAddress: 192.168.6.1
          peerConfigRef:
            name: l3-bgp-peer-config
        - name: router-mine-zt
          peerASN: 64513
          peerAddress: 192.168.191.12 # 路由器的 ZeroTier IP
          peerConfigRef:
            name: l3-bgp-peer-config
```

同时，确保 Cilium 开启了 PodCIDR 通告（修复了之前配置遗漏的问题），以便路由器能学习到 Pod 网段路由。

### 2. 路由器 BIRD 配置 (`/etc/bird.conf`)

修改远程节点的协议配置，直接使用其 **ZeroTier IP** 建立邻居关系，并**移除源地址绑定**。

```bird
protocol bgp yuuko_k8s from k8s {
    # 使用远程节点的 ZeroTier IP，而不是物理/LAN IP
    neighbor 192.168.191.10 as K8S_ASN;
    
    # 跨网段必须开启 Multihop
    multihop 2;
    
    # 移除 source address 限制，允许 BIRD 自动选择最佳接口 IP (即 ZeroTier IP)
    # source address 192.168.6.1; <--- 注释掉或删除
}
```

### 3. 路由器防火墙 (必须)

OpenWrt 的区域转发规则通常仅覆盖接口定义的网段。由于 Pod 网段 (`10.42.0.0/16`) 不属于任何物理接口，必须显式添加规则允许其在 LAN 和 VPN 区域间转发。

```config
# /etc/config/firewall

# 允许本地 Pod 访问远程 Pod/节点
config rule
    option name 'Allow-K8s-Pod-Lan-to-Zt'
    option src 'lan'
    option dest 'zt'
    list dest_ip '10.42.0.0/16'
    option target 'ACCEPT'

# 允许远程 Pod 访问本地 Pod/节点
config rule
    option name 'Allow-K8s-Pod-Zt-to-Lan'
    option src 'zt'
    option dest 'lan'
    list dest_ip '10.42.0.0/16'
    option target 'ACCEPT'
```

## 总结

对于跨网段/VPN 连接的 K8s 节点，**最佳实践是直接使用 VPN 网络的 IP (Overlay IP) 建立 BGP 会话**。这避免了复杂的 NAT 穿透问题、源地址校验问题以及 MTU 问题，是能够“一次打通”的最稳健方案。