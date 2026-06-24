# 新增 K8s 服务 - 参考指南

## 基础原则

- **配置克制** — 字段只有在当前服务明确需要时才写。
- **依赖显式** — 数据库、缓存、密钥、存储、Volsync 这类前置条件，出现在 `dependsOn` 或 `components` 里。
- **复用范式** — 优先参考仓库中结构相近的应用，不发明新摆法。
- **密钥** — 通过 `ExternalSecret` 进入集群。
- **安全** — 安全配置优先从现有应用复制，再按镜像实际要求收紧或放宽。

## 模式库

### basic-ks.yaml

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
  namespace: &namespace default
spec:
  targetNamespace: *namespace
  dependsOn:
    - name: <dependency>
      namespace: <namespace>
  path: ./k8s/apps/common/<app-name>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: false
  interval: 1h
  retryInterval: 2m
  timeout: 5m
```

### basic-kustomization.yaml

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./externalsecret.yaml     # 只在真正存在时引用
```

### configmap-generator

```yaml
configMapGenerator:
  - name: <app-name>-config
    files:
      - config.yaml=./resources/config.yaml
generatorOptions:
  disableNameSuffixHash: true
```

### envfrom-secret

```yaml
envFrom:
  - secretRef:
      name: <app-name>-secret
```

## 参考目录

| 场景 | 目录 |
|------|------|
| 简单服务 | `k8s/apps/common/echo/` |
| 带密钥 | `k8s/apps/common/vaultwarden/` |
| 带数据库 | `k8s/apps/common/affine/` |
| 带配置文件生成 | `k8s/apps/common/cli-proxy-api/` |
| 带 init-db | `k8s/apps/common/memos/`、`k8s/apps/common/shlink/` |
