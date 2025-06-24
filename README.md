# home-ops
homelab



## 设备网络

> lb ip range: 192.168.6.40 ~ 192.168.6.49

| 服务             | ip           |
| ---------------- | ------------ |
| k8s-gateway      | 192.168.6.41 |
| external gateway | 192.168.6.45 |
| internal gateway | 192.168.6.46 |
| cilium ingress   | 192.168.6.40 |

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
