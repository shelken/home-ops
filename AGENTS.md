# AGENTS.md

为 AI 代码助手提供项目指引。

## 最高原则

- 使用中文对话
- 任何资源的删除操作必须询问确认之后才可以执行

## 项目概述

此仓库 `home-ops` 用于管理个人 homelab Kubernetes 集群，采用 GitOps 原则。

### 核心技术栈
- **容器编排**: Kubernetes (k3s)
- **GitOps**: Flux CD v2
- **网络**: Cilium, Multus, Envoy Gateway
- **密钥**: SOPS + External-Secrets + Azure KeyVault
- **存储**: Longhorn, CloudNative-PG

### 关键目录
- `k8s/apps/common/` - 应用部署
- `k8s/infra/common/` - 基础设施
- `k8s/components/` - 可复用组件
- `k8s/clusters/staging/` - Flux 监控目录
- `bootstrap/` - 集群引导
- `.taskfile/` - Task 子任务

## 开发环境

使用 Nix Flake 管理，详见 `flake.nix`。

关键环境变量：
- `KUBECONFIG`: `./kubeconfig`
- `SOPS_AGE_KEY_FILE`: `~/.config/sops/age/keys.txt`

## 常用命令

参考 `Taskfile.yaml` 和 `.taskfile/` 目录。

```bash
task --list              # 查看所有任务
```
