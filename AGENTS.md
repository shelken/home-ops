# 项目上下文

## 对话原则

- 使用中文对话

## 项目概述

此代码仓库 `home-ops` 包含用于管理个人 homelab Kubernetes 集群的基础设施即代码 (IaC) 定义和自动化脚本。主要目标是使用 GitOps 原则以声明方式管理集群的状态、应用程序和配置。

## 目录结构

> 待补充

## 构建和运行

### GitOps 工作流 (Flux)

集群引导完成且 Flux 运行后（通过 `bootstrap/helmfile.yaml` 部署并通过 `k8s/infra/common/flux-system/flux-instance` 配置），它会接管持续协调过程。Flux 监视本仓库中的 `k8s/clusters/staging` 目录。提交到此仓库的任何更改都将由 Flux 自动应用到集群。

## 开发约定

- **密钥**：所有密钥都存储在 `*.sops.yaml` 文件中，并使用 SOPS 进行管理和加密。`.sops.yaml` 文件定义了加密规则和密钥。
- **配置**：Kubernetes 配置主要存储在 `k8s/` 目录中的 YAML 清单中，通常使用 Kustomize 或 Helm 进行模板化和自定义。
- **自动化**：常见操作任务封装在 `Taskfile.yaml` 中，以确保一致性和易于执行。
- **基础设施**：核心基础设施组件（CNI、DNS、Cert-Manager 等）通过 Helm 图表定义和部署，在 `bootstrap/` 和 `k8s/infra/` 中配置。

## 技能

### 添加普通服务

#### 描述

往集群引入某个普通服务

#### 详细

当我们需要往集群加入某个普通服务时，我们通常在`k8s/apps/common`下加上一个子目录，并通常已echo服务作为模板，适当进行修改，然后在`kustomization.yaml`中引入。

原则

- 除非特殊，否则我们均会以`app-template`作为chart
- 有secret的话，一般引入`externalsecret.yaml`来添加，结构可以找项目中其他同名文件参考
- 如果需要添加组件，从`k8s/components`下来引入组件
