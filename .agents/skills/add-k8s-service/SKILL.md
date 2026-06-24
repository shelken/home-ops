---
name: add-k8s-service
description: 在 home-ops 仓库中为 k3s 集群新增服务的完整流程：设计→创建代码→提交审查→部署观测。按 Flux GitOps 双层结构（infra.yml 与 apps.yml）组织文件与依赖。使用当用户要求部署新应用、添加新服务、补齐 app 目录资源时。
---

# 新增 K8s 服务

## Quick start

```text
<parent-dir>/<app-name>/
├── ks.yaml                  # Flux 入口
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml     # app-template chart
    ├── externalsecret.yaml  # 需要密钥时创建
    └── resources/           # 需要配置文件时创建
```

`<parent-dir>` 按服务归属决定（见创建代码第 1 步）。

1. 找 1-3 个最接近的现有目录当模板。
2. 创建上述目录结构，只写当前服务真正需要的文件。
3. 注册到对应当层的 `kustomization.yaml`。
4. `kustomize build` 验证 app、对应中间层、staging 三层。

## Workflows

### 0. 设计（可选）

复杂服务先写设计文档到 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`，提交后等用户审查。审查通过再写代码。

对于需求尚不明确的服务，可用 [brainstorming skill](../../../../../.agents/skills/brainstorming/SKILL.md) 逐条澄清设计后再写代码。

### 1. 创建代码

1. **识别形态与归属** — 先判断服务属于 apps 还是 infra：
   - 普通应用 → `k8s/apps/common/<app>/`
   - 基础设施（网络、存储、监控等）→ `k8s/infra/common/<category>/<app>/`
   - 外部入口（caddy-external、ss-rust 这类） → `k8s/infra/common/network/external/<app>/`

   然后判断技术特征：HTTP? DB? 密钥? 持久化? route? 选参考目录。
2. **写 `ks.yaml`** — `dependsOn` 只写真实前置，`components` 只写用到的能力。
3. **写 `helmrelease.yaml`** — 优先 app-template。镜像、env、service、route、persistence、probes、resources 按需补齐。
4. **写 `kustomization.yaml`** — 只引用真实存在的文件。有配置文件需要生成 ConfigMap 再加 `configMapGenerator`。
5. **写 `externalsecret.yaml`** — 需要密钥才创建。`dataFrom.extract.key` 用真实的 Azure KeyVault secret 名，`target.template.data` 只暴露服务实际消费的键。
6. **写入 KeyVault** — 用 `task secret:set-key secret=<keyvault-name> key=<字段名> value=<值>` 把密钥写入 Azure KeyVault。agent 不得读取敏感值。
7. **注册** — 加进对应层的 `kustomization.yaml`：
   - apps 服务 → `k8s/apps/common/kustomization.yaml`
   - infra 服务 → 对应的 category 层，如 `k8s/infra/common/network/external/kustomization.yaml`
   保持排序风格。
8. **验证** — `kustomize build` 跑三层：
   - apps： `app/` → `k8s/apps/common/` → `k8s/apps/staging/`
   - infra： `app/` → `<category>/`  →  `k8s/infra/staging/`

### 2. 提交审查

代码写完不自行提交。等用户审查同意后，再提 PR。

### 3. 部署观测

PR 合并后，触发 Flux 部署链并确认服务正常运行。

**部署链路（详见 docs/ARCHITECTURE.md §8）：**

```
GitHub (main branch)
  │
  ▼  flux bootstrap
k8s/clusters/staging/
  ├── repos.yaml  →  OCIRepository: app-template
  │
  ├── infra.yml  (Flux Kustomization, wait: true)
  │     │  patches: sops + subst → 全部子级
  │     ▼
  │   k8s/infra/staging/  (kustomize build)
  │     │  imports: ../common/{network, database, ...}
  │     ▼
  │   k8s/infra/common/{category}/kustomization.yaml
  │     │
  │     ▼
  │   <app>/ks.yaml  (子级 Flux Kustomization CRD)
  │     │  sourceRef: GitRepository flux-system
  │     │  path: ./app/
  │     ▼
  │   app/ → HelmRelease → Pod
  │
  └── apps.yml  (Flux Kustomization, dependsOn: infra, wait: false)
        │  patches: sops + subst → 全部子级
        ▼
      k8s/apps/staging/  (kustomize build)
        │  imports: ../common/
        ▼
      k8s/apps/common/kustomization.yaml
        │
        ▼
      <app>/ks.yaml  (子级 Flux Kustomization CRD)
        │  sourceRef: GitRepository flux-system
        │  path: ./app/
        ▼
      app/ → HelmRelease → Pod
```

**操作：**

```bash
# 触发对应层
flux reconcile ks infra -n flux-system          # infra 服务
flux reconcile ks apps -n flux-system           # apps 服务

# 等具体 app 就绪
# apps 服务（通常是 Deployment）
kubectl rollout status deployment/<app> -n <namespace> --timeout=5m
# infra 服务（部分不是 Deployment，如 DaemonSet/StatefulSet）
kubectl get pods -n <namespace> -l app.kubernetes.io/name=<app> -w
```

Pod 未就绪时检查日志定位问题。

## Anti-patterns

- 不要为"看起来完整"补无关字段。
- 不要把依赖全写上——每个都要说清用途。
- 不要预先创建不需要的文件。
- 不要把参考目录整块复制过来，逐项按需删减。
- 不要擅自加标签（`labels`）、`mergePolicy`。

## Validation

- 目录两层结构？`ks.yaml` → `app/`。
- `path` 指向正确（apps → `./k8s/apps/common/<app>/app`，infra → `./k8s/infra/common/<category>/<app>/app`）？
- `kustomization.yaml` 只引真实存在的文件？
- 字段、依赖、标签都有明确理由？
- 注册层和 staging 渲染通过？

## Reference

- 模式库与 YAML 示例：See [REFERENCE.md](REFERENCE.md)
- 目录规范：`.agents/skills/home-ops-conventions/SKILL.md`
