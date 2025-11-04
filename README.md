---
<h3 align="center">
<img src="https://wsrv.nl?url=https://avatars.githubusercontent.com/u/33972006?fit=cover&mask=circle&maxage=7d" width="100" alt="Logo"/><br/>
<img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/misc/transparent.png" height="30" width="0px"/>
<img src="https://gcore.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/kubernetes-dashboard.svg" height="15" /> Homelab for <a href="https://github.com/shelken">Shelken</a>
<img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/misc/transparent.png" height="30" width="0px"/>
</h3>

<p align="center">
<img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/palette/macchiato.png" width="400" />
</p>

<div align="center">

[![K3S](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fk3s_version&logo=k3s&labelColor=363a4f&style=for-the-badge&label=K3S&color=91D7E3)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_age_days&logo=upptime&labelColor=363a4f&style=for-the-badge&label=Age)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_uptime_days&logo=upptime&labelColor=363a4f&style=for-the-badge&label=Uptime)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_node_count&logo=kubernetes&labelColor=363a4f&style=for-the-badge&label=Nodes)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_pod_count&logo=kubernetes&labelColor=363a4f&style=for-the-badge&label=Pods)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_cpu_usage&labelColor=363a4f&style=for-the-badge&label=CPU)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_memory_usage&labelColor=363a4f&style=for-the-badge&label=Memory)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fcluster_alert_count&logo=prometheus&labelColor=363a4f&style=for-the-badge&label=Alerts)](https://prometheus.ooooo.space/alerts)

</div>
---

# home-ops

homelab

## 设备网络

> lb ip range: 192.168.6.40 ~ 192.168.6.59

| 服务                       | ip               | 描述           | domain      |
| -------------------------- | ---------------- | -------------- | ----------- |
| k8s-gateway                | 192.168.6.41     | 开放给外部 dns |             |
| nginx internal ingress     | 192.168.6.43     |                |             |
| ~~nginx external ingress~~ | ~~192.168.6.44~~ | 已经关闭       |             |
| envoy external gateway     | 192.168.6.45     |                |             |
| envoy internal gateway     | 192.168.6.46     |                |             |
| home assistant             | 192.168.6.51     |                |             |
| postgres17                 | 192.168.6.52     | 开放postgres   | postgres17. |
| go2rtc                     | 192.168.6.53     |                |             |
| plex                       | 192.168.6.54     |                |             |
| scrypted                   | 192.168.6.55     |                |             |
| immich-db                  | 192.168.6.56     |                |             |
| seafile-db                 | 192.168.6.57     |                |             |
| qbittorrent                | 192.168.6.58     |                |             |
| mosquitto                  | 192.168.6.59     |                |             |
| longhorn                   |                  | longhorn ui    | longhorn.   |
| ~~cilium ingress~~         | ~~192.168.6.40~~ | 已经关闭       |             |

## 服务网络

| 服务 | 状态                                                                            |
| ---- | ------------------------------------------------------------------------------- |
| echo | ![](https://status.ooooo.space/api/v1/endpoints/external_echo/health/badge.svg) |

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

## 初始化所需Secret

> 以下secret存储在 Azure KeyVault 或任何 external secret 提供商
>
> [resources](/bootstrap/resources.yaml)

| secret key      | 用途                                                      | 备注 |
| --------------- | --------------------------------------------------------- | ---- |
| azure-creds     | external-secret 获取secret必须                            |      |
| flux-instance   | flux-instance 拉取private repo必须                        |      |
| sops            | 部分使用sops加密的配置                                    |      |
| ooooo-space-tls | 域名证书（加快集群部署速,度避免cert-manager多次获取证书） |      |

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

3. envoy-gateway 对 grpc-web 协议直接过滤成 grpc，目前无法关闭，在memos服务使用时调用出错

暂时使用nginx ingress作为入口

4. 每次重建集群之后，cilium总是不给gateway ip

`task restart-cilium` 重启后正常了

5. lima 无法挂载磁盘

```json
{
  "level": "fatal",
  "msg": "failed to run attach disk \"longhorn\", in use by instance \"sakamoto-k8s\"",
  "time": "2025-07-08T14:24:21+08:00"
}
```

`limactl disk unlock longhorn`

6. 迁移secret后， external-secrets 无法push

因为external-secret azure会自动给pushsecret打上tag，表示由external-secret管理，迁移时没有加上这个tag

导致出现问题, 删掉secret让external-secret重新同步。

6. longhorn 的daemonset在重启k3s或者机器时存在Misscheduled的情况

删掉对应 pod 解决

非常奇怪。。。。。。

7. smb 中文乱码问题

宿主机缺失相关动态库

```shell
sudo apt-get install -y cifs-utils linux-modules-extra-$(uname -r)
```

8. 遇到helmrelease/kustomization卡住的情况

```shell
flux suspend helmrelease cilium -n kube-system
flux resume helmrelease cilium -n kube-system
```
