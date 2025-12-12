# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 最高原则

- 使用中文对话
- 任何资源的删除操作必须询问确认之后才可以执行

## 项目概述

此代码仓库 `home-ops` 包含用于管理个人 homelab Kubernetes 集群的基础设施即代码 (IaC) 定义和自动化脚本。主要目标是使用 GitOps 原则以声明方式管理集群的状态、应用程序和配置。

## 架构概览

### 核心组件
- **容器编排**: Kubernetes (k3s)
- **GitOps**: Flux CD v2
- **网络**: Cilium (eBPF), Multus (多网络接口)
- **入口**: Envoy Gateway
- **证书**: Cert-Manager
- **密钥管理**: SOPS + External-Secrets + Azure KeyVault
- **存储**: Longhorn (分布式存储), CloudNative-PG (PostgreSQL)
- **监控**: Prometheus Stack
- **配置管理**: Ansible
- **任务自动化**: Taskfile

### 目录结构
```
home-ops/
├── ansible/                    # Ansible 自动化配置
├── bootstrap/                  # 集群引导配置 (Cilium, CoreDNS, Cert-Manager, External-Secrets, Flux)
├── docs/                       # 文档
├── k8s/                        # Kubernetes 配置 (核心)
│   ├── apps/                  # 应用程序配置
│   │   ├── common/           # 通用应用 (按应用名组织)
│   │   └── staging/          # 暂存环境应用
│   ├── clusters/             # 集群配置
│   │   ├── staging/         # 暂存集群配置 (Flux 监控此目录)
│   │   ├── production/      # 生产集群配置
│   │   └── common/          # 通用集群配置
│   ├── components/          # 可复用组件 (alerts, sops, authelia, envoy-gateway-oidc 等)
│   └── infra/               # 基础设施配置
│       ├── common/         # 通用基础设施 (cert-manager, flux-system, longhorn-system 等)
│       └── staging/        # 暂存环境基础设施
├── scripts/                    # 脚本文件
├── Taskfile.yaml              # 任务自动化配置文件
├── .sops.yaml                 # SOPS 加密配置 (Age 密钥)
├── .taskfile/                 # Taskfile 子任务配置
│   ├── sops.yaml             # SOPS 相关任务
│   ├── secret.yaml           # 密钥管理任务
│   └── flux.yaml             # Flux 相关任务
└── bootstrap/                 # 集群引导
    ├── helmfile.yaml         # 初始 Helm 部署
    ├── crds.yaml             # CRD 初始化
    └── resources.yaml        # 初始资源定义
```

## 常用命令

### 集群管理
```bash
# 完整集群引导 (Ansible + k3s 部署)
task bootstrap

# 初始化 CRD
task init-crd

# 集群初始化 (部署核心组件)
task init

# 重启 Cilium (解决 L2 宣告问题)
task restart-cilium
```

### GitOps 工作流 (Flux)
集群引导完成且 Flux 运行后（通过 `bootstrap/helmfile.yaml` 部署并通过 `k8s/infra/common/flux-system/flux-instance` 配置），它会接管持续协调过程。Flux 监视本仓库中的 `k8s/clusters/staging` 目录。提交到此仓库的任何更改都将由 Flux 自动应用到集群。

```bash
# 查看路由配置
task show-route

# 暂停/恢复 HelmRelease
flux suspend helmrelease <name> -n <namespace>
flux resume helmrelease <name> -n <namespace>
```

### 密钥管理
```bash
# 使用 SOPS 编辑加密文件
task sops:edit -- <file>

# 加密文件
task sops:encrypt -- <file>

# 解密文件
task sops:decrypt -- <file>
```

### 开发工具
```bash
# 在 PVC 上运行临时 Pod
task kube-run --image=busybox:latest --pvc=<pvc-name>

# 浏览 PVC 内容
task browse-pvc --namespace=<ns> --claim=<pvc-name>

# 计算相对路径
task relpath --start=<start-file> --end=<end-dir>
```

## 开发约定

### 密钥管理
- 所有密钥都存储在 `*.sops.yaml` 文件中，并使用 SOPS 进行管理和加密
- `.sops.yaml` 文件定义了加密规则和密钥 (使用 Age 加密)
- 加密规则：匹配 `k8s/.+\.sops\.(ya?ml)` 文件
- 加密字段：`data` 和 `stringData`

### 配置管理
- Kubernetes 配置主要存储在 `k8s/` 目录中的 YAML 清单中
- 使用 Kustomize 或 Helm 进行模板化和自定义
- 通用配置放在 `k8s/components/common/`

### 应用部署模式
1. **普通服务**: 在 `k8s/apps/common/<app-name>/app/` 下创建目录
2. **使用模板**: 以 `app-template` Helm chart 作为标准模板
3. **密钥管理**: 使用 `externalsecret.yaml` 从 Azure KeyVault 同步密钥
4. **组件引用**: 从 `k8s/components/` 引入可复用组件
5. **环境配置**: 通过 `k8s/clusters/<env>/` 管理环境特定配置

### 网络配置
- **L2 宣告**: 用于需要固定 IP 的服务 (IP 范围: 192.168.69.40-59)
- **Multus**: 仅用于需要 IPv6 或 mDNS 的服务
- **外部访问**: 通过 Envoy Gateway (外部)

## 疑难问题解决

### 常见问题
1. **Cilium L2 宣告问题**: `task restart-cilium`
2. **Flux HelmRelease 卡住**: 暂停后恢复
3. **Multus 设备占用**: 避免使用滚动更新
4. **Longhorn 卸载**: 先设置删除确认标志
5. **External-Secrets 同步失败**: 检查 Azure KeyVault 标签

### 网络问题
- **L2 宣告失败**: 删除对应的 lease `kubectl delete lease <name> -n kube-system`
- **Multus 使用场景**: 仅用于 IPv6 直连或 mDNS 服务
- **滚动更新限制**: 避免用于有 Multus 或 ReadWriteOnce PVC 的服务

## 环境配置

### 当前环境
- **暂存环境**: `k8s/clusters/staging/` (主要开发环境)
- **生产环境**: `k8s/clusters/production/` (预留)

### IP 地址规划
- **LB IP 范围**: 192.168.69.40-59
- **Multus 网络**: 192.168.6.0/24
- **Tailscale**: 192.168.6.64/29, 192.168.6.65/29

### 核心服务 IP
- k8s-gateway: 192.168.69.41
- envoy external gateway: 192.168.69.45
- envoy internal gateway: 192.168.69.46
- postgres-lb: 192.168.69.52

## 技能

### 添加普通服务

#### 描述
往集群引入某个普通服务

#### 详细
当我们需要往集群加入某个普通服务时，我们通常在`k8s/apps/common`下加上一个子目录，并通常已echo服务作为模板，适当进行修改，然后在`kustomization.yaml`中引入。

#### 原则
- 除非特殊，否则我们均会以`app-template`作为chart
- 有secret的话，一般引入`externalsecret.yaml`来添加，结构可以找项目中其他同名文件参考
- 如果需要添加组件，从`k8s/components`下来引入组件
