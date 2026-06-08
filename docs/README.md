# 文档索引

本目录记录 home-ops 的架构、部署、网络、存储、运维和历史设计。公开文档采用半公开运维版：隐藏公网域名、公网 IP、系统/SSH 登录用户名、密钥路径和私有服务 URL；保留公开 GitHub 仓库链接、内网网段、节点名、设备名和架构关系，方便排障。

## 核心入口

| 文档 | 用途 |
|------|------|
| [架构总览](./ARCHITECTURE.md) | 物理部署、网络入口、服务分布、监控采集和备份链路 |
| [网络清单](./network-inventory.md) | LoadBalancer、Multus 和固定服务地址清单 |
| [运维笔记](./operations-notes.md) | Flux、Cilium、Multus、SMB 等常见排障入口 |
| [路由器配置](./router/README.md) | OpenWrt、BGP、VLAN、mDNS 相关配置 |
| [尸检报告](../postmortems/README.md) | 已发生事故的根因、误判和复盘规则 |

## 部署与基础设施

| 文档 | 用途 |
|------|------|
| [Proxmox 创建虚拟机](./1-proxmox创建虚拟机.md) | PVE VM 模板和节点创建记录 |
| [部署 k3s](./2-部署k3s.md) | k3s 安装与历史命令记录 |
| [Flux GitOps](./3-flux-cicd.md) | Flux 引导、密钥和同步说明 |
| [Cilium](./5-cni-cilium.md) | Cilium 安装、BGP 和网络相关记录 |
| [密钥管理](./6-secrets.md) | SOPS、External Secrets 和 bootstrap secret |
| [Renovate](./7-renovate.md) | 镜像和依赖升级自动化 |
| [升级](./8-upgrade.md) | 集群升级相关记录 |
| [Lima on Mac Mini](./9-lima-with-m4-mac-mini.md) | Lima VM 配置与磁盘记录 |

## 存储、备份与服务

| 文档 | 用途 |
|------|------|
| [OpenEBS HostPath](./10-openebs-hostpath.md) | OpenEBS 卷固定到 sakamoto 的记录 |
| [Volsync](./11-volsync.md) | PVC 备份与恢复记录 |
| [Tailscale](./12-tailscale.md) | Tailscale operator 和代理记录 |
| [MinIO](./13-minio.md) | S3 存储和访问策略记录 |
| [网络](./14-network.md) | IPv6、node-ip 等网络记录 |
| [GPU](./15-gpu.md) | GPU 驱动、插件和直通记录 |
| [重建后手动操作](./16-重建后需要手动的操作.md) | 重建集群后仍需人工处理的事项 |
| [CrowdSec](./18-crowdsec.md) | CrowdSec LAPI、VPS agent、bouncer 和 AppSec 运维 |
| [VPS IP 变更](./19-vps-ip-change.md) | VPS 地址变化后的处理清单 |

## 历史和草案

| 文档 | 状态 |
|------|------|
| [跨地域节点互联](./17-add-remote-node.md) | 历史参考，相关节点已离线 |
| [Talos](./talos.md) | 草案/调研 |
| [Talos 迁移分析](./draft/talos-migration-analysis.md) | 草案/调研 |
| [ServiceMonitor 排查报告](./draft/servicemonitor.md) | 草案/历史排查 |
| [Cloudflare Tunnel 与公网直连切换](./cftunnel与直接公网切换.md) | 历史迁移记录 |

## 维护规则

- 新增长期有效文档时，优先把入口加到本索引。
- 临时排查结论不要直接堆进 README；可先写入对应服务文档或 postmortem。
- 涉及公网域名、公网 IP、系统/SSH 登录用户名、密钥路径、私有服务 URL 时使用占位符；公开 GitHub 仓库链接不需要脱敏。
- 涉及直接删除资源、绕过 GitOps 或 bootstrap 例外命令时，必须在文档中标明适用场景和风险。
