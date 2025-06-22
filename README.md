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


## flux

### 疑难问题

1. `dry-run failed: no matches for kind "OCIRepository in version "source.toolkit.fluxcd.io/v1`

检查cli安装的版本，版本太低与文件定义的api版本和实际版本对不上。

直接升级cli版本，然后Bootstrap 让flux自动升级。

ocirepo 在 2.6上才是v1，在2.5上配置是v1beta2
