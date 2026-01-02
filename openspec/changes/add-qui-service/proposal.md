# Change: Add Qui Service

## Why

qBittorrent 作为集群中的下载服务已经部署，但缺少一个现代化、统一的 WebUI 管理界面。Qui 是 autobrr 团队开发的现代化 qBittorrent WebUI，可以从单一界面管理多个 qBittorrent 实例，提供更好的用户体验和跨实例管理能力。

## What Changes

- 新增 `k8s/apps/common/qui/` 目录，包含完整的 Kubernetes 部署配置
- 创建 Flux Kustomization 资源 (`ks.yaml`)
- 创建 HelmRelease 使用 app-template chart 部署 Qui
- 创建 ExternalSecret 从 Azure KeyVault 获取 session secret
- 配置 volsync 组件进行数据备份
- 通过 envoy-internal 网关暴露服务

## Impact

- Affected specs: qui-deployment (新增)
- Affected code:
  - `k8s/apps/common/qui/ks.yaml` - Flux Kustomization
  - `k8s/apps/common/qui/app/helmrelease.yaml` - HelmRelease
  - `k8s/apps/common/qui/app/externalsecret.yaml` - ExternalSecret
  - `k8s/apps/common/qui/app/kustomization.yaml` - Kustomize 资源清单
  - `k8s/apps/common/kustomization.yaml` - 需要添加 qui 引用
- 需要在 Azure KeyVault 中创建 `qui` secret，包含 `QUI-SESSION-SECRET` 字段
