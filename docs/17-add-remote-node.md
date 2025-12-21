# 跨地域节点互联架构 (BGP 全互联方案)

本文档记录了将异地节点（`yuuko-k8s`）接入本地 K3s 集群并实现 **Native Routing (原生路由)** 的最终架构方案。

此方案通过在两端路由器上运行 BGP 协议，打通了跨地域的 Pod 网络，实现了无需手动维护静态路由、无需 Overlay 封装的高性能三层互通。

## 1. 网络拓扑

### 架构概览

*   **本地网络 (Mine)**: `192.168.6.0/24`
*   **远程网络 (Home)**: `192.168.0.0/24`
*   **互联链路 (VPN)**: ZeroTier `192.168.191.0/24`
*   **Pod 网络**: `10.42.0.0/16` (Native Routing)

### BGP 拓扑图

```mermaid
graph TD
    subgraph "Remote Site (Home)"
        Yuuko[Node: yuuko-k8s<br>IP: 192.168.0.81<br>AS: 64514]
        R_Home[Router: Home<br>LAN: 192.168.0.1<br>ZT: 192.168.191.10<br>AS: 64515]
    end

    subgraph "Local Site (Mine)"
        R_Mine[Router: Mine<br>LAN: 192.168.6.1<br>ZT: 192.168.191.12<br>AS: 64513]
        Sakamoto[Node: sakamoto<br>IP: 192.168.6.80<br>AS: 64514]
        OtherNodes[Other Nodes...]
    end

    %% Connections
    Yuuko -- "eBGP (LAN)" --> R_Home
    R_Home -- "eBGP (ZeroTier)" --> R_Mine
    R_Mine -- "iBGP (LAN)" --> Sakamoto
    R_Mine -- "iBGP (LAN)" --> OtherNodes

    %% Routing Flow
    Yuuko -.-> |"Advertise 10.42.3.0/24"| R_Home
    R_Home -.-> |"Forward 10.42.3.0/24"| R_Mine
    R_Mine -.-> |"Learn 10.42.3.0/24"| Sakamoto
```

### ASN 分配

| 设备 | ASN | 角色 |
| :--- | :--- | :--- |
| **router-mine** | 64513 | 本地核心网关 |
| **router-home** | 64515 | 远程中继网关 |
| **Cilium (所有节点)** | 64514 | K8s Pod 网络 |

## 2. 关键配置

### 2.1 路由器配置 (BIRD)

> **详细配置**: 请参阅 [路由器 BGP 配置](./router/bgp.md)

两端路由器均需安装 `bird2`，配置要点：

- **router-mine (AS 64513)**: 核心网关，连接本地 K8s 节点，通过 ZeroTier 连接远程路由器
- **router-home (AS 64515)**: 中继网关，连接远程节点 Yuuko，转发路由到本地

### 2.2 Cilium 配置 (BGP)

使用 `CiliumBGPClusterConfig` 的 `nodeSelector` 功能，将本地节点和远程节点指向各自的**本地网关**。

**文件**: `k8s/infra/common/kube-system/cilium/app/networks.yaml`

```yaml
# 本地节点配置：连接 192.168.6.1
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: bgp-local
spec:
  nodeSelector:
    matchExpressions:
      - key: node-type
        operator: NotIn
        values: ["remote"]
  bgpInstances:
    - name: cilium
      localASN: 64514
      peers:
        - name: router-mine
          peerASN: 64513
          peerAddress: 192.168.6.1
          peerConfigRef:
            name: l3-bgp-peer-config

---
# 远程节点配置：连接 192.168.0.1
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: bgp-remote
spec:
  nodeSelector:
    matchLabels:
      node-type: remote # Yuuko 需打上此标签
  bgpInstances:
    - name: cilium
      localASN: 64514
      peers:
        - name: router-home
          peerASN: 64515
          peerAddress: 192.168.0.1
          peerConfigRef:
            name: l3-bgp-peer-config
```

### 2.3 防火墙与路由

*   **OpenWrt 防火墙**: 依靠标准的 Zone Forwarding (`lan <-> zt`)。无需针对 Pod 网段添加特殊的 NAT 或 Rule，因为路由表已经指明了去向。
*   **静态路由**: **不需要**。BGP 会自动维护所有 Pod CIDR 的路由。

## 3. 验证方法

1.  **检查路由表**:
    *   在 `router-mine` 上 `ip route | grep 10.42`，应看到远程 Pod 网段 `via 192.168.191.10`。
    *   在 `router-home` 上 `ip route | grep 10.42`，应看到本地 Pod 网段 `via 192.168.191.12`。

2.  **Pod 互通**:
    *   从本地 Pod Ping 远程 Pod IP (`10.42.3.x`)，应无丢包。

3.  **节点监控**:
    *   `kubectl top node yuuko-k8s` 应正常显示数据。

## 4. 优势总结

1.  **架构解耦**: K8s 配置与底层物理网络拓扑解耦，节点只需知道自己的网关。
2.  **自动收敛**: 新增节点或 Pod 网段变化时，路由自动更新，无需维护静态路由表。
3.  **高性能**: 全程 Native Routing，无 Overlay 封装开销，MTU 利用率最大化。

## 5. 相关文档

- [路由器 BGP 配置](./router/bgp.md) - BIRD 完整配置文件
- [路由器 VLAN 配置](./router/vlan.md) - VLAN 网络划分
- [路由器配置索引](./router/README.md) - 所有路由器配置汇总