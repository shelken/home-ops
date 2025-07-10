---

<div align="center">

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_age_days&style=flat-square&label=Age)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_uptime_days&style=flat-square&label=Uptime)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_node_count&style=flat-square&label=Nodes)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_pod_count&style=flat-square&label=Pods)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_cpu_usage&style=flat-square&label=CPU)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_memory_usage&style=flat-square&label=Memory)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_alert_count&style=flat-square&label=Alerts)](https://github.com/kashalls/kromgo)

</div>

---
# home-ops
homelab



## 设备网络

> lb ip range: 192.168.6.40 ~ 192.168.6.59

| 服务                    | ip               | 描述           | domain      |
| ----------------------- | ---------------- | -------------- | ----------- |
| k8s-gateway             | 192.168.6.41     | 开放给外部 dns |             |
| nginx external ingress  | 192.168.6.44     |                |             |
| cilium external gateway | 192.168.6.45     |                |             |
| nginx internal ingress  | ~~192.168.6.43~~ | 暂时关闭 无用  |             |
| cilium internal gateway | 192.168.6.46     |                |             |
| cilium internal gateway | 192.168.6.46     |                |             |
| postgres17              | 192.168.6.52     | 开放postgres   | postgres17. |
| longhorn                |                  | longhorn ui    | longhorn.   |
| cilium ingress          | ~~192.168.6.40~~ | 已经关闭       |             |

## 核心组件

### Core Components

- [cert-manager](https://github.com/cert-manager/cert-manager): Creates SSL certificates for services in my cluster.
- [cilium](https://github.com/cilium/cilium): eBPF-based networking for my workloads.
- [external-dns](https://github.com/kubernetes-sigs/external-dns): Automatically syncs ingress DNS records to a DNS provider.
- [k8s-gateway](https://github.com/k8s-gateway/k8s_gateway): https://github.com/k8s-gateway/k8s_gateway
<!-- - [external-secrets](https://github.com/external-secrets/external-secrets): Managed Kubernetes secrets using [1Password Connect](https://github.com/1Password/connect). -->
<!-- - [rook](https://github.com/rook/rook): Distributed block storage for peristent storage. -->
- [sops](https://github.com/getsops/sops): Managed secrets for Kubernetes and Terraform which are commited to Git.
<!-- - [spegel](https://github.com/spegel-org/spegel): Stateless cluster local OCI registry mirror. -->
<!-- - [volsync](https://github.com/backube/volsync): Backup and recovery of persistent volume claims. -->


## flux

### 疑难问题

1. `dry-run failed: no matches for kind "OCIRepository in version "source.toolkit.fluxcd.io/v1`

检查cli安装的版本，版本太低与文件定义的api版本和实际版本对不上。

直接升级cli版本，然后Bootstrap 让flux自动升级。

ocirepo 在 2.6上才是v1，在2.5上配置是v1beta2

2. 卸载longhorn（删除helmrelease）前

```shell
kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
```

3. cilium-gateway 对 grpc-web 协议直接过滤成 grpc，目前无法关闭，在memos服务使用时调用出错

暂时使用nginx ingress作为入口

4. 每次重建集群之后，cilium总是不给gateway ip

`task restart-cilium` 重启后正常了

5. lima 无法挂载磁盘
   
```json
{"level":"fatal","msg":"failed to run attach disk \"longhorn\", in use by instance \"sakamoto-k8s\"","time":"2025-07-08T14:24:21+08:00"}
```

`limactl disk unlock longhorn` 