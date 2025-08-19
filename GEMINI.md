# Qwen Code 的项目上下文

## 项目概述

此代码仓库 `home-ops` 包含用于管理个人 homelab Kubernetes 集群的基础设施即代码 (IaC) 定义和自动化脚本。主要目标是使用 GitOps 原则以声明方式管理集群的状态、应用程序和配置。

使用的核心技术包括：
- **Kubernetes (K3s)**：容器编排平台。
- **FluxCD**：GitOps 操作符，持续将集群状态与本仓库中的定义进行协调。
- **Helm/Helmfile**：用于打包和部署核心基础设施应用程序。
- **Ansible**：用于初始节点配置和 Kubernetes 部署前的配置。
- **SOPS (Secrets OPerationS)**：用于管理和加密仓库中的密钥。
- **Cilium**：容器网络接口 (CNI)，提供网络、可观察性和安全性。
- **Taskfile**：任务运行器，用于定义和执行常见操作命令。

## 目录结构

- `README.md`：项目介绍、网络布局、核心组件和故障排除说明。
- `Taskfile.yaml` & `.taskfile/`：用于常见任务（如引导、密钥管理和调试）的集中命令。
- `ansible/`：用于初始操作系统设置（主机名、时区、软件包）和 K3s 安装先决条件的 Ansible playbook。
- `bootstrap/`：初始设置资源，包括用于部署核心基础设施组件（Cilium、CoreDNS、Cert-Manager、Flux Operator/Instance）的 Helmfile。
- `k8s/`：主要的 Kubernetes 资源定义，按集群 (`clusters/staging`) 和基础设施组件 (`infra/common`) 组织。
- `scripts/`：实用的 shell 脚本。
- `.sops.yaml` & `.taskfile/sops.yaml`：SOPS 加密的配置和用于管理加密文件的 Taskfile 目标。

## 构建和运行

### 先决条件
- `task` (Taskfile 运行器)
- `ansible` 和 `ansible-playbook`
- `kubectl`
- `helm` 和 `helmfile`
- `sops` 和 `age` 用于密钥管理
- 访问目标 Kubernetes 集群节点（用于引导）。

### 关键命令
这些命令在 `Taskfile.yaml` 中定义，使用 `task <command>` 执行。

- **引导集群（初始设置）**：
  ```bash
  task bootstrap
  task init
  ```
  - `task bootstrap`：使用 Ansible 在集群节点上准备操作系统级设置（主机名、时区、软件包）并配置 K3s 先决条件（如 containerd 镜像）。
  - `task init`：通过应用必要的 CRD、使用 `helmfile` 部署核心基础设施组件和引导密钥来初始化集群。

- **密钥管理**：
  ```bash
  task sops:encrypt-all
  task sops:updatekey-all
  ```
  - `task sops:encrypt-all`：查找所有 `*.sops.yaml` 文件并在它们尚未加密时进行加密。
  - `task sops:updatekey-all`：更新所有现有 `*.sops.yaml` 文件的加密密钥。

- **调试和实用工具**：
  ```bash
  task show-route
  task restart-cilium
  ```
  - `task show-route`：显示 Ingress 和 HTTPRoute 的摘要。
  - `task restart-cilium`：重启 Cilium 部署和守护进程集，对于解决网络问题很有用。

### GitOps 工作流 (Flux)

集群引导完成且 Flux 运行后（通过 `bootstrap/helmfile.yaml` 部署并通过 `k8s/infra/common/flux-system/flux-instance` 配置），它会接管持续协调过程。Flux 监视本仓库中的 `k8s/clusters/staging` 目录。提交到此仓库的任何更改都将由 Flux 自动应用到集群。

## 开发约定

- **密钥**：所有密钥都存储在 `*.sops.yaml` 文件中，并使用 SOPS 进行管理和加密。`.sops.yaml` 文件定义了加密规则和密钥。
- **配置**：Kubernetes 配置主要存储在 `k8s/` 目录中的 YAML 清单中，通常使用 Kustomize 或 Helm 进行模板化和自定义。
- **自动化**：常见操作任务封装在 `Taskfile.yaml` 中，以确保一致性和易于执行。
- **基础设施**：核心基础设施组件（CNI、DNS、Cert-Manager 等）通过 Helm 图表定义和部署，在 `bootstrap/` 和 `k8s/infra/` 中配置。