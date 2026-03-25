# AGENTS.md

为 AI 代码助手提供项目指引。

## 最高原则

- 如无必要，勿增实体，使用中文对话
- 使用最少权限原则来写任何配置，任何提高权限的配置必须给出十足的理由，理由必须来自官方 配置/文档/发布日志 里的说明，附上链接
- Gitops原则，flux管理，只有调试时才可以使用apply，调试完成后恢复原来的，然后提交git，并使用`direnv exec . flux reconcile`
- 任何组件的新的配置的变更，必须有关于官方 配置/文档/发布日志 的引用（可以直接跳转的链接），否则不允许直接变更任何配置
- 任何资源的删除操作必须询问确认之后才可以执行
- 执行kubectl前必须带上`KUBECONFIG=./kubeconfig`
- 执行测试kubectl apply前需要考虑namepsace（因为资源的namespace一般不写，由flux管理）
- SSH执行命令时优先使用IP地址而非主机名（参考ansible节点信息表中的IP列）
- 遇到失败的helmrelease，不要reconcile，直接删除，然后reconcile ks
- 需要容器镜像时，寻找最新镜像固定化镜像版本，配合renovate的更新
- 优先使用`Conventional Commits`格式提交git commit，title中文，body中文，如果有`git-commit`，`git-commit`优先

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

## 集群节点信息

| 节点名 | 角色 | 宿主机 | CPU | 内存 | 架构 | IP | 系统盘 | Longhorn 存储 |
|--------|------|--------|-----|------|------|-----|--------|---------------|
| sakamoto-k8s | control-plane, etcd | Mac Mini M4 (4P+6E 核, Lima VM, vz) | 8 vCPU | 14GB | arm64 | 192.168.6.80 | 80GB | 1TB SSD |
| homelab-1 | worker | 笔记本 PVE (Intel i5-7300HQ 4核) VM | 4 核 | 14GB | amd64 | 192.168.6.110 | 321GB | 共用系统盘 |
| yuuko-k8s | worker | Mac Mini M1 (4P+4E 核, Lima VM, vz) | 6 vCPU | 14GB | arm64 | 192.168.6.81 | 40GB | 无 |

### 节点说明

- **sakamoto-k8s**: 唯一的控制平面节点，承载 etcd 和主要工作负载，Longhorn 主存储节点
- **homelab-1**: 七代 Intel CPU 的 PVE 虚拟机，Longhorn 副本节点
- **yuuko-k8s**: 节点（192.168.6.81）

### Lima VM 配置文件

- `docs/resource/lima/sakamoto.yaml` - sakamoto-k8s 配置
- `docs/resource/lima/yuuko.yaml` - yuuko-k8s 配置


## 开发环境

使用 Nix Flake + direnv 管理。找不到命令时尝试使用 `direnv exec . <command>` 包装以加载正确的环境。

## 常用命令

参考 `Taskfile.yaml` 和 `.taskfile/` 目录。

```bash
task --list              # 查看所有任务
```
