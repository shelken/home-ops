---
name: add-k8s-service
description: 在 home-ops 仓库中为 Kubernetes 集群新增普通服务，并按现有 GitOps 结构组织文件与依赖。使用当用户要求部署新应用、添加新服务、补齐 app 目录资源时。
---

# 新增 K8s 服务

## Quick start

```text
k8s/apps/common/<app-name>/
├── ks.yaml                  # Flux 入口
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml     # app-template chart
    ├── externalsecret.yaml  # 需要密钥时创建
    └── resources/           # 需要配置文件时创建
```

1. 找 1-3 个最接近的现有目录当模板。
2. 创建上述目录结构，只写当前服务真正需要的文件。
3. 注册到 `k8s/apps/common/kustomization.yaml`。
4. `kustomize build` 验证 app、common、staging 三层。

## Workflows

1. **识别形态** — HTTP? DB? 密钥? 持久化? route? 然后选参考目录。
2. **写 `ks.yaml`** — `dependsOn` 只写真实前置，`components` 只写用到的能力。
3. **写 `helmrelease.yaml`** — 优先 app-template。镜像、env、service、route、persistence、probes、resources 按需补齐。
4. **写 `kustomization.yaml`** — 只引用真实存在的文件。有配置文件需要生成 ConfigMap 再加 `configMapGenerator`。
5. **写 `externalsecret.yaml`** — 需要密钥才创建。`dataFrom.extract.key` 用真实的 Azure KeyVault secret 名。
6. **注册** — 加进 `k8s/apps/common/kustomization.yaml`，保持排序风格。
7. **验证** — `kustomize build` 跑 app/、common/、staging/ 三层。

## Anti-patterns

- 不要为"看起来完整"补无关字段。
- 不要把依赖全写上——每个都要说清用途。
- 不要预先创建不需要的文件。
- 不要把参考目录整块复制过来，逐项按需删减。
- 不要擅自加标签（`labels`）、`mergePolicy`。

## Validation

- 目录两层结构？`ks.yaml` → `app/`。
- `path` 指向 `./k8s/apps/common/<app>/app`？
- `kustomization.yaml` 只引真实存在的文件？
- 字段、依赖、标签都有明确理由？
- staging 渲染通过？

## Reference

- 模式库与 YAML 示例：See [REFERENCE.md](REFERENCE.md)
- 目录规范：`.agents/skills/home-ops-conventions/SKILL.md`
