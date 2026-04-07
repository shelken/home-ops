## 最高原则

- 如无必要，勿增实体，使用中文对话
- 使用最少权限原则来写任何配置，任何提高权限的配置/任何组件的新的配置的变更 必须给出十足的理由，理由必须来自官方 配置/文档/发布日志 里的说明，附上链接
- GitOps原则，Flux管理，只有调试时才可以使用`kubectl apply`，调试完成后恢复原来的，然后提交git，并使用`direnv exec . flux reconcile`
- 任何资源的删除操作必须询问确认之后才可以执行
- 执行kubectl前确保使用direnv里面自带的环境变量（引用当前目录下的kubeconfig）
- 优先使用`Conventional Commits`格式提交git commit，title**y英文**，body**中文**，如果有`git-commit`，读取`git-commit`作为补充

## 项目概述

此仓库 `home-ops` 用于管理个人 homelab Kubernetes 集群

### 架构

- **容器编排**: Kubernetes (k3s)
- **GitOps**: Flux CD v2
- **网络**: Cilium, Multus, Envoy Gateway, External-DNS
- **密钥**: SOPS + External-Secrets + Azure KeyVault
- **存储**: Longhorn, CloudNative-PG, SMB
- **备份**: Volsync, Minio

### 关键目录

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

- 目前使用 Nix Flake + direnv 管理。找不到命令时尝试使用 `direnv exec . <command>` 包装以加载正确的环境。
- 在 `k8s/apps/common/` 中关闭某个应用时，需要同步检查 `.renovate/packageRules.json5` 的 `Disabled Packages`，把该应用相关的镜像/包一并加入，避免继续产生 Renovate PR；重新开启该应用时，也要同步从 `Disabled Packages` 中移除对应项
- 需要容器镜像时，寻找最新镜像固定化镜像版本，配合renovate的更新
- 遇到失败的helmrelease，不要reconcile，直接删除，然后reconcile ks
- SSH执行命令时优先使用IP地址而非主机名（参考[ansible节点信息](ansible/inventory/hosts.ini)）
- 执行测试`kubectl apply`前需要考虑namepsace（因为资源的namespace一般不写，由flux管理）

## 常用命令/脚本

参考 `Taskfile.yaml` 和 `.taskfile/` 目录。

```bash
task --list              # 查看所有任务
```
