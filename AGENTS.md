# AGENTS.md

为 AI 代码助手提供项目指引。

## 最高原则

- 使用中文对话
- 任何资源的删除操作必须询问确认之后才可以执行
- 执行kubectl前必须带上`KUBECONFIG=./kubeconfig`

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
| tvbox | worker | S905x3 电视盒子 (Armbian) | 4 核 | 4GB | arm64 | 192.168.6.141 | 28GB eMMC | 无 |
| yuuko-k8s | worker | Mac Mini M1 (4P+4E 核, Lima VM, vz) | 6 vCPU | 14GB | arm64 | 192.168.0.81 | 40GB | 无 |

### 节点说明

- **sakamoto-k8s**: 唯一的控制平面节点，承载 etcd 和主要工作负载，Longhorn 主存储节点
- **homelab-1**: 七代 Intel CPU 的 PVE 虚拟机，Longhorn 副本节点
- **tvbox**: 低功耗 ARM 电视盒子，运行轻量级工作负载，无持久存储
- **yuuko-k8s**: 远程节点（192.168.0.x 网段），通过 ZeroTier VPN 连接，不参与 Longhorn 存储

### Lima VM 配置文件

- `docs/resource/lima/sakamoto.yaml` - sakamoto-k8s 配置
- `docs/resource/lima/yuuko.yaml` - yuuko-k8s 配置

### 节点特殊配置 (Taints & Labels)

- **tvbox**
  - Taint: `dedicated=lightweight:NoSchedule`
  - Label: `node-type=lightweight`
  - 说明: 仅允许容忍了 `dedicated=lightweight` 的轻量级应用调度。

- **yuuko-k8s**
  - Taint: `dedicated=remote:NoSchedule`
  - Label: `node-type=remote`
  - 说明: 远程节点，仅允许容忍了 `dedicated=remote` 的应用调度。

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
