<h3 align="center">
<img src="https://wsrv.nl?url=https://avatars.githubusercontent.com/u/33972006?fit=cover&mask=circle&maxage=7d" width="100" alt="Logo"/><br/>
<img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/misc/transparent.png" height="30" width="0px" alt="transparent"/>
<img src="https://gcore.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/kubernetes-dashboard.svg" height="15" alt="kubernetes-dashboard" /> Homelab for <a href="https://github.com/shelken">Shelken</a>
<img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/misc/transparent.png" height="30" width="0px" alt="transparent"/>
</h3>

<p align="center">
<img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/palette/macchiato.png" width="400" alt="color-bar"/>
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

[![MiFi-Network](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fmifi_network_type&logo=wifi&labelColor=363a4f&style=for-the-badge&label=Network)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![MiFi-Operator](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fmifi_operator&logo=simpleicons&labelColor=363a4f&style=for-the-badge&label=Operator)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![MiFi-Monthly](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.ooooo.space%2Fmifi_monthly_total&logo=chart-bar&labelColor=363a4f&style=for-the-badge&label=Monthly)](https://github.com/kashalls/kromgo)

</div>

&nbsp;

# home-ops

Homelab GitOps 仓库。Kubernetes 集群、基础设施组件、应用、外部 Compose 服务、备份和运维文档都从这里管理。

## 架构摘要

- 容器编排：Kubernetes / k3s
- GitOps：Flux CD v2
- 网络：Cilium、Multus、Envoy Gateway、External-DNS
- 密钥：SOPS、External Secrets、Azure KeyVault
- 存储：Longhorn、CloudNativePG、SMB
- 备份：Volsync、MinIO、Kopia
- 外部服务：`compose/sakamoto/`、`compose/vps/`

完整架构见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 文档入口

| 文档 | 用途 |
|------|------|
| [`docs/README.md`](docs/README.md) | 文档总索引 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 物理部署、服务分布、入口流量、监控采集、备份链路 |
| [`docs/network-inventory.md`](docs/network-inventory.md) | LoadBalancer、Multus 和固定服务地址清单 |
| [`docs/operations-notes.md`](docs/operations-notes.md) | 常见 Flux、Cilium、Longhorn、SMB、Multus 排障入口 |
| [`docs/router/README.md`](docs/router/README.md) | OpenWrt、BGP、VLAN、mDNS 配置 |
| [`postmortems/README.md`](postmortems/README.md) | 事故复盘和长期规则 |

## 重要路径

| 路径 | 用途 |
|------|------|
| `k8s/clusters/staging/kustomization.yaml` | Flux 监控的应用与基础设施入口 |
| `k8s/apps/common/` | 应用部署 |
| `k8s/infra/common/` | 基础设施部署 |
| `k8s/components/` | 可复用组件模板 |
| `compose/sakamoto/` | sakamoto Docker Compose 服务 |
| `compose/vps/` | VPS Docker Compose 服务 |
| `bootstrap/` | 集群引导资源 |
| `ansible/` | 节点初始化和系统配置 |
| `.taskfile/` | Task 子任务定义 |
| `docs/` | 架构、部署和运维文档 |

## 工作原则

- 常规变更走 Git + Flux，不直接 `kubectl apply`。
- 资源删除必须先确认目标和影响范围。
- 本地未提交/未推送的文件不是集群状态。
- 新增或禁用 `k8s/apps/common/` 应用时，同步维护 `.renovate/packageRules.json5`。
- 需要暴露单独地址时，优先确认 LoadBalancer、Multus、Gateway、External-DNS 的责任边界。
- 需要容器镜像时固定版本和 digest，并交给 Renovate 后续更新。

## 常用命令

```shell
task --list
```

更多命令见 [`Taskfile.yaml`](Taskfile.yaml) 和 `.taskfile/`。
