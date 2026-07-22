## 最高原则

- 所有配置默认遵循最小权限原则;任何权限提升或新增的安全敏感配置变更，必须引用官方文档、配置参考或发布日志作为依据，并附上来源链接
- GitOps原则，Flux管理，不准执行`kubectl apply`，不准直接对集群进行操作
- 任何资源的删除操作必须确认之后才可以执行
- 区分哪些文件是集群的状态，哪些是当前的工作区状态要区分，不要认为本地未提交或未推送的代码就等于集群
- 公开仓库内容不准暴露真实域名、公网 IP、内网 IP、节点名、主机名、系统/SSH 登录用户名、绝对路径、密钥路径、私有服务 URL；写文档、尸检报告、示例命令、日志摘录时必须用占位符（如 `<ROUTER_IP>`、`<PROXY_DOMAIN>`、`<NODE_NAME>`、`<PRIVATE_PATH>`），除非用户明确要求保留真实值；分析排障和理解配置时可以读取并使用真实值，不要因为脱敏影响判断；公开 GitHub 仓库 URL / owner 不属于这里的“用户名”，不要脱敏
- 如果必须执行命令操作集群, 记住自己的手动执行命令, 必须在解决问题之后检查哪些命令会对集群产生残留影响, 必须列出来告诉用户; 如果忘记了, 检查auditlog; 并且在解决问题后, 恢复残留操作

## 架构

**完整架构文档**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 物理部署、网络拓扑、服务分布、入口流量、监控采集、备份链路。不清楚系统架构时先读这个。

- **容器编排**: Kubernetes (k3s)
- **GitOps**: Flux CD v2
- **网络**: Cilium, Multus, Envoy Gateway, External-DNS
- **密钥**: SOPS + External-Secrets + Azure KeyVault
- **存储**: Longhorn, CloudNative-PG, SMB
- **备份**: Volsync, Minio

### 重要路径索引

**集群管理**
- `k8s/clusters/staging/kustomization.yaml`: Flux 监控的应用与基础设施入口
- `k8s/apps/common/`: 应用部署
- `k8s/infra/common/`: 基础设施（网络、监控、数据库、存储）
- `k8s/components/`: 可复用组件模板（Volsync、ExternalSecret 等）

**网络**
- `k8s/infra/common/network/external/`: 外部入口（Caddy、Cloudflare DNS）
- `k8s/infra/common/network/internal/`: 内部网络（openwrt-dns、zte-mifi-healer、k8s-gateway）
- `k8s/infra/common/network/envoy-gateway/`: Envoy Gateway 配置与路由
- `k8s/infra/common/network/tailscale/`: Tailscale proxy 与 subnet router
- `docs/router/`: router-mine (OpenWrt) 配置文档

**集群外服务**
- `compose/sakamoto/`: sakamoto Docker Compose 服务
- `compose/vps/`: VPS Docker Compose 服务

**基础设施**
- `bootstrap/`: 集群引导
- `ansible/`: Ansible 控制
- `.taskfile/`: Task 子任务定义
- `docs/resource/lima/`: Lima VM 配置文件

> **注意**: 发现路径变更时，向用户确认是否同步更新文档。

## 集群节点信息

| 节点名       | 角色          | 所在                         | CPU    | 内存 | 架构  | IP            | 系统盘 | Longhorn 存储 |
| ------------ | ------------- | ---------------------------- | ------ | ---- | ----- | ------------- | ------ | ------------- |
| sakamoto-k8s | control-plane | Mac Mini M4（lima vm中）     | 8 vCPU | 14GB | arm64 | 192.168.6.80  | 80GB   | 1TB SSD       |
| homelab-1    | worker        | PVE (Intel i5-7300HQ 4核) VM | 4 核   | 14GB | amd64 | 192.168.6.110 | 321GB  | 共用系统盘    |

### Lima VM 配置文件

- `docs/resource/lima/sakamoto.yaml` - sakamoto-k8s 配置
- `docs/resource/lima/yuuko.yaml` - yuuko-k8s 配置

## Notes

- 进入 repo 目录后 mise 自动加载工具与环境变量（含 kubeconfig）。直接执行命令即可，无需额外包装
- 新的skill描述全部中文描述
- 在 `k8s/apps/common/` 启用/禁用某个应用时，同步更新 `.renovate/packageRules.json5` 的 `Disabled Packages`：禁用时添加该应用相关的镜像/包；启用时移除。
- 当多个服务同属一个目的时，优先放在同一个应用目录下按职责拆分子目录，例如 `aistudio-proxy-api/app/` 和 `aistudio-proxy-api/login/`，再由同级 `ks.yaml` 引用这些路径。
- 需要容器镜像时，寻找最新镜像固定化镜像版本（semver@digest），配合renovate的更新
- 遇到失败的helmrelease，不要reconcile，直接删除hr，然后`flux reconcile ks`
- SSH执行命令时优先使用IP地址而非主机名（参考[ansible节点信息](ansible/inventory/hosts.ini)）

## 常用命令/脚本

参考 `Taskfile.yaml` 和 `.taskfile/` 目录。

```bash
task --list # 查看命令
```

## Agents Remind

### 自维护镜像源码位置

- `zte-mifi-exporter`（集群部署在 `k8s/apps/common/zte-mifi-exporter/`）的源码不在本仓库，在外部 `containers` 仓库的 `apps/zte-mifi-exporter/` 下。需要改 exporter 指标逻辑、抓取字段时，去 containers 仓库改源码并构建镜像，再回 home-ops 更新镜像 tag。

### 自愈告警约定

- 自愈类 PrometheusRule 告警的 label 应精确描述动作语义，便于 Alertmanager 路由与抑制；新增动作类告警用 `action: <动词-对象>`（如 `f50-disconnect-cellular`），不要复用笼统的 `autoheal`。
- 自愈动作相互冲突时用 `inhibitRules` 协调：主动动作的告警 active 期间，抑制会与之冲突的被动自愈告警（如主动断蜂窝后抑制 `autoheal: f50-network` 的 reconnect，避免反复拨号耗流量）。
