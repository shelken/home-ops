## 最高原则

- 所有配置默认遵循最小权限原则;任何权限提升或新增的安全敏感配置变更，必须引用官方文档、配置参考或发布日志作为依据，并附上来源链接
- GitOps原则，Flux管理，不准执行`kubectl apply`，不准直接对集群进行操作
- 任何资源的删除操作必须确认之后才可以执行
- 区分哪些文件是集群的状态，哪些是当前的工作区状态要区分，不要认为本地未提交或未推送的代码就等于集群

## 开发/重构/优化 Workflow 规范

- 功能开发、重构、性能优化统一遵循本节
- 读相关代码、注释、计划文档，同步记录不明确项，读完后一次性确认，确认完毕再继续
- 写 interface/type 定义，不写实现
- 列出实现步骤 + 所有检查点，写入 PLAN.md（清空旧内容）；检查点必须为单独一节，放在文件最开头，只能按顺序往下增加
- 按步骤逐一实现，每步完成后：在 PLAN.md 检查点节标记进度并记录结论/偏差，执行 `pre-commit run`，通过后提交
- 主代理使用子代理做完整审阅；审查代码必须用独立子代理；给足目标、变更范围、风险点、已踩坑、审查焦点
- 子代理报问题后先复核再修；修完后由**同一个**子代理复审；若发现设计级问题，回到步骤列表重新规划
- 确认 PLAN.md 所有项已完成且无遗留，执行最终 `pre-commit run` 兜底，确认无误

## 架构

- **容器编排**: Kubernetes (k3s)
- **GitOps**: Flux CD v2
- **网络**: Cilium, Multus, Envoy Gateway, External-DNS
- **密钥**: SOPS + External-Secrets + Azure KeyVault
- **存储**: Longhorn, CloudNative-PG, SMB
- **备份**: Volsync, Minio

## 关键目录

- `k8s/apps/common/` - 应用部署
- `k8s/infra/common/` - 基础设施
- `k8s/components/` - 可复用组件
- `k8s/clusters/staging/` - Flux 监控目录(目前)
- `bootstrap/` - 集群引导
- `compose/` - 集群之外手动管理
- `.taskfile/` - Task 子任务
- `ansible/` - ansible控制

## 集群节点信息

| 节点名       | 角色          | 所在                         | CPU    | 内存 | 架构  | IP            | 系统盘 | Longhorn 存储 |
| ------------ | ------------- | ---------------------------- | ------ | ---- | ----- | ------------- | ------ | ------------- |
| sakamoto-k8s | control-plane | Mac Mini M4（lima vm中）     | 8 vCPU | 14GB | arm64 | 192.168.6.80  | 80GB   | 1TB SSD       |
| homelab-1    | worker        | PVE (Intel i5-7300HQ 4核) VM | 4 核   | 14GB | amd64 | 192.168.6.110 | 321GB  | 共用系统盘    |

### Lima VM 配置文件

- `docs/resource/lima/sakamoto.yaml` - sakamoto-k8s 配置
- `docs/resource/lima/yuuko.yaml` - yuuko-k8s 配置

## 重要笔记

- repo 目录下的命令默认继承 direnv 环境（含 kubeconfig 等环境变量）。仅在命令找不到或无法连接集群时，用 `direnv exec . <cmd>` 包装一次。不要对每条命令都使用
- 提交格式 使用`git-commit`skill；仓库不使用jj
- 新的skill描述全部中文描述
- 在 `k8s/apps/common/` 启用/禁用某个应用时，同步更新 `.renovate/packageRules.json5` 的 `Disabled Packages`：禁用时添加该应用相关的镜像/包；启用时移除。
- 需要容器镜像时，寻找最新镜像固定化镜像版本（semver@digest），配合renovate的更新
- 遇到失败的helmrelease，不要reconcile，直接删除hr，然后`flux reconcile ks`
- SSH执行命令时优先使用IP地址而非主机名（参考[ansible节点信息](ansible/inventory/hosts.ini)）

## 常用命令/脚本

参考 `Taskfile.yaml` 和 `.taskfile/` 目录。

```bash
task --list # 查看命令
```
