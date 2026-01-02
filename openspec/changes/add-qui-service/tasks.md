# Tasks: Add Qui Service

## 1. 准备工作

- [ ] 1.1 在 Azure KeyVault 中创建 `qui` secret，包含 `QUI-SESSION-SECRET` 字段

## 2. 创建 Kubernetes 资源

- [x] 2.1 创建目录结构 `k8s/apps/common/qui/app/`
- [x] 2.2 创建 `k8s/apps/common/qui/ks.yaml` - Flux Kustomization
- [x] 2.3 创建 `k8s/apps/common/qui/app/kustomization.yaml` - Kustomize 资源清单
- [x] 2.4 创建 `k8s/apps/common/qui/app/externalsecret.yaml` - ExternalSecret
- [x] 2.5 创建 `k8s/apps/common/qui/app/helmrelease.yaml` - HelmRelease

## 3. 集成到 Flux

- [x] 3.1 更新 `k8s/apps/common/kustomization.yaml` 添加 qui 引用

## 4. 验证部署

- [ ] 4.1 检查 Flux Kustomization 状态
- [ ] 4.2 检查 HelmRelease 状态
- [ ] 4.3 检查 Pod 运行状态
- [ ] 4.4 通过网关访问 Qui WebUI 验证功能
