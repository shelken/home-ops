# Tailscale

## 使用 Tailscale 连接 VPS 与家庭内网

> 网络限制：集群节点为单栈 IPv4，无法直接进行 IPv6 节点直连
>
> 处理方案：通过 ProxyClass 定义受管代理资源，为 Class 绑定 Multus IPv6 网卡（已落地于 `k8s/infra/common/network/tailscale/proxy/`，网卡定义见 `k8s/infra/common/network/multus/networks/ipv6.yaml`）

### 官方参考

- [Tailscale Kubernetes Operator Docs](https://github.com/tailscale/tailscale/tree/main/docs/k8s)
- [Docker Tailscale Guide](https://tailscale.com/kb/1282/docker)
- [Kubernetes Operator Overview](https://tailscale.com/kb/1236/kubernetes-operator)
- [Exposing Cluster Workloads via Annotations](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress#exposing-a-cluster-workload-by-annotating-an-existing-service)

### 部署要素

1. 安装 `kubernetes-operator`
2. 配置 OAuth Client 与 `tagOwner` 权限标签
3. 在网关或 Service 资源添加注解暴露内网端点

Tailscale Operator 在集群内部监控目标资源生命周期，按需派生代理 Pod 并向 Tailscale 控制平面注册对应接入节点
