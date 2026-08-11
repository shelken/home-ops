home-ops 是使用 Flux 管理 Kubernetes 集群与集群外服务的 GitOps 配置仓库。

## 基本约束

- 所有配置默认遵循最小权限原则;任何权限提升或新增的安全敏感配置变更，必须引用官方文档、配置参考或发布日志作为依据，并附上来源链接
- GitOps原则，Flux管理，不准执行`kubectl apply`，不准直接对集群进行操作
- 在你运维任何问题时, 必须给我把问题相关的架构搞清楚. 阅读 `docs/ARCHITECTURE.md` 先把整体搞清楚
- **infra → apps**：运维/debug/恢复时永远先让 `flux-system/infra` Ready（含其 wait/health 依赖），再处理 `apps`。apps 依赖 infra；infra 未通时禁止靠长期旁路子 ks 顶替 parent
- 任何资源的删除操作必须确认之后才可以执行
- 区分哪些文件是集群的状态，哪些是当前的工作区状态要区分，不要认为本地未提交或未推送的代码就等于集群
- 公开仓库内容不准暴露真实域名、公网 IP、内网 IP、节点名、主机名、系统/SSH 登录用户名、绝对路径、密钥路径、私有服务 URL；写文档、尸检报告、示例命令、日志摘录时必须用占位符（如 `<ROUTER_IP>`、`<PROXY_DOMAIN>`、`<NODE_NAME>`、`<PRIVATE_PATH>`），除非用户明确要求保留真实值；分析排障和理解配置时可以读取并使用真实值，不要因为脱敏影响判断；公开 GitHub 仓库 URL / owner 不属于这里的“用户名”，不要脱敏
- 如果必须执行命令操作集群, 记住自己的手动执行命令, 必须在解决问题之后检查哪些命令会对集群产生残留影响, 必须列出来告诉用户; 如果忘记了, 检查auditlog; 并且在解决问题后, 恢复残留操作

## 架构

**完整架构文档**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 物理部署、网络拓扑、服务分布、入口流量、监控采集、备份链路。不清楚系统架构时先读这个。

- **容器编排**: Kubernetes (k3s)
- **GitOps**: Flux CD v2；staging 根 Kustomization 依次装载仓库源、infra 和 apps，apps 显式依赖 infra
- **网络**: Cilium、Multus、Envoy Gateway、External-DNS、Tailscale
- **密钥**: SOPS、External-Secrets、Azure Key Vault
- **数据库与缓存**: CloudNative-PG、Dragonfly
- **存储**: Longhorn、OpenEBS、SMB CSI
- **备份**: VolSync 使用 Kopia，将备份写入集群外 MinIO
- **可观测性**: Prometheus、Grafana、Gatus、VictoriaLogs

### 重要目录索引

**集群与 GitOps**
- `k8s/clusters/`: Flux 集群入口、仓库源及 infra/apps 父级编排
- `k8s/apps/common/`: 应用通用配置
- `k8s/apps/staging/`: staging 应用聚合入口
- `k8s/infra/common/`: 网络、证书、密钥、数据库、存储、监控和安全等基础设施
- `k8s/infra/staging/`: staging 当前启用的基础设施聚合入口
- `k8s/components/`: VolSync、SOPS、认证和调度等可复用组件

**网络与集群外服务**
- `k8s/infra/common/network/`: 内外 DNS、入口网关、Multus、证书、Tailscale 和网络自愈组件
- `docs/router/`: OpenWrt 路由器配置文档与资源
- `compose/sakamoto/`: sakamoto Docker Compose 服务及配置
- `compose/vps/`: VPS Docker Compose 服务及配置

**引导、自动化与维护**
- `bootstrap/`: 集群引导配置
- `ansible/`: 节点清单与配置自动化
- `.taskfile/`: Task 子任务定义
- `.renovate/`: Renovate 分组、规则和自定义管理器
- `scripts/`: 可重复运行的运维与维护脚本
- `tests/`: 配置和脚本测试
- `postmortems/`: 已解决复杂问题的尸检报告
- `docs/resource/`: Lima 等基础设施资源配置

> **注意**: 发现路径或组件状态变化时，同步检查本索引和 `docs/ARCHITECTURE.md`。

### Lima VM 配置文件

- `docs/resource/lima/sakamoto.yaml` - sakamoto-k8s 配置

## 项目约定

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

## 参考仓库

- [`onedr0p/home-ops`](https://github.com/onedr0p/home-ops): 架构与配置模式的上游参考
- `kaiyuan/homelab/home-ops`: 上游仓库的本地参考副本(每次拉最新再看)
