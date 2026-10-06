# home-ops

home-ops 是使用 Flux 管理 Kubernetes 集群与集群外服务的 GitOps 配置仓库。

## 约束

- 集群由 Flux 管理：变更一律走 Git 提交，禁止 `kubectl apply`，禁止直接操作集群
- 运维顺序固定 infra → apps：先让 `flux-system/infra` Ready（含其 wait/health 依赖），再处理 `apps`；infra 就绪前不得用旁路子 Kustomization 顶替 parent
- 删除任何资源前必须先确认
- 手动执行过的集群命令，事后必须列出对集群的残留影响并恢复，忘记执行过什么时回查 audit log
- 公开仓库脱敏：写出的内容不得出现真实域名、公网或内网 IP、节点名、主机名、SSH 登录用户名、绝对路径、密钥路径与私有服务 URL，一律用占位符；排障时可以直接读取真实值

## 阅读场景

- 排障、运维、恢复或不清楚架构与入口 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，依赖顺序与等待策略见其中「Flux 部署链路」
- 写代码、改配置、新增应用 → [CODING_STANDARDS.md](CODING_STANDARDS.md)
- 找文档、确认文档归属 → [docs/README.md](docs/README.md)
- 排查历史事故与已知坑 → [postmortems/README.md](postmortems/README.md)
- 在 compose/、ansible/、.taskfile/ 下工作 → 先读对应目录的 AGENTS.md

## 布局

- `k8s/`: Flux 集群声明（clusters、infra、apps、components）
- `compose/`、`router/`、`lima/`: 集群外 Compose 服务、路由器配置源、Lima VM（见 [lima/README.md](lima/README.md)）
- `ansible/`、`bootstrap/`: 节点配置自动化、集群引导
- `.taskfile/`、`scripts/`、`.renovate/`: task 命令入口、运维脚本、依赖升级配置
- `docs/`、`postmortems/`: 文档索引、尸检报告
