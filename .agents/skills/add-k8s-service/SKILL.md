---
name: add-k8s-service
description: 在 home-ops 仓库中为 Kubernetes 集群新增普通服务，并按现有 GitOps 结构组织文件与依赖。用于用户要求部署新应用、添加新服务、补齐 app 目录资源时。
---

<objective>
在 `home-ops` 仓库里新增一个普通 Kubernetes 服务，产出符合当前仓库习惯的 `ks.yaml`、`app/kustomization.yaml`、`app/helmrelease.yaml`，以及按需新增的 `externalsecret.yaml`、`resources/*`。

这个技能的重点有两个：一是目录和依赖关系贴合仓库现状；二是配置保持克制，只有在当前服务确实需要时才写入字段。
</objective>

<quick_start>
先做这几件事：

1. 读现有同类应用，优先找结构接近的参考。
2. 确认新服务属于 `k8s/apps/common/<app-name>/`。
3. 只写当前服务真正需要的配置。
4. 把 `ks.yaml` 接进 `k8s/apps/common/kustomization.yaml`。
5. 用 `kustomize build` 校验新目录和 staging 入口。

基础目录：

```text
k8s/apps/common/<app-name>/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml
    ├── externalsecret.yaml   # 仅在需要密钥时创建
    └── resources/            # 仅在需要额外配置文件时创建
```
</quick_start>

<context>
这个仓库使用 Flux GitOps。应用目录固定两层：外层 `ks.yaml` 作为 Flux 入口，内层 `app/` 放应用资源。

文件归属遵循项目约定：谁负责这件事，文件就放谁那里。路由、密钥、额外配置文件都跟着应用目录走。
</context>

<essential_principles>
- 配置保持克制。字段只有在当前服务明确需要时才写。
- 依赖显式声明。数据库、缓存、密钥、存储、Volsync 这类前置条件，出现在 `dependsOn` 或 `components` 里。
- 复用现有范式。优先参考仓库中结构相近的应用，不发明新摆法。
- 密钥通过 `ExternalSecret` 进入集群。
- 路由写在 `HelmRelease` 里，和 service 一起维护。
- 安全配置优先从现有应用复制，再按镜像实际要求收紧或放宽。
</essential_principles>

<process>
1. **识别服务形态**
   - 先判断它属于哪一类：
     - 纯 HTTP 服务
     - 带数据库初始化
     - 需要外部密钥
     - 需要持久化存储
     - 需要额外配置文件
     - 需要 internal / external route
   - 再找 1 到 3 个最接近的现有目录当模板。

2. **创建目录**
   - 固定创建：
     - `k8s/apps/common/<app-name>/ks.yaml`
     - `k8s/apps/common/<app-name>/app/kustomization.yaml`
     - `k8s/apps/common/<app-name>/app/helmrelease.yaml`
   - 按需创建：
     - `app/externalsecret.yaml`
     - `app/resources/*`

3. **写 ks.yaml**
   - 固定字段参考现有应用：`name`、`namespace`、`targetNamespace`、`path`、`sourceRef`、`interval`、`retryInterval`、`timeout`、`wait`。
   - `dependsOn` 只写真实前置条件。
   - `components` 只在当前服务确实使用对应能力时引入，例如 `volsync`、`authelia`。
   - 标签只在当前仓库已有明确语义且当前服务确实需要时添加。

4. **写 helmrelease.yaml**
   - 优先使用 `app-template`。
   - `controllers.<app>.containers.app.image` 填镜像与版本。
   - `env` 只写当前服务必要变量。
   - `envFrom` 只在当前服务需要整包 Secret 时使用。
   - `service`、`route`、`persistence`、`defaultPodOptions` 按当前服务需求补齐。
   - 健康检查优先复用上游已有健康接口。
   - `resources` 始终显式设置。

5. **写 kustomization.yaml**
   - 默认只列真实存在的资源。
   - 如果有配置文件需要生成 ConfigMap，再加 `configMapGenerator`。
   - 如果有 `externalsecret.yaml`，再把它加入 `resources`。

6. **写 externalsecret.yaml**
   - 只在服务需要密钥、数据库初始化参数、第三方 API key 时创建。
   - `dataFrom.extract.key` 使用真实的 Azure Key Vault secret 名。
   - `target.template.data` 只写当前服务运行时真正会消费的键。

7. **注册到上层 kustomization**
   - 把 `<app-name>/ks.yaml` 加进 `k8s/apps/common/kustomization.yaml`。
   - 维持当前文件的排序风格与注释风格。

8. **验证**
   - 运行：
     - `kustomize build k8s/apps/common/<app-name>/app`
     - `kustomize build k8s/apps/common`
     - `kustomize build k8s/apps/staging`
   - 检查生成结果里：
     - 资源路径正确
     - Secret 引用存在
     - Route hostname 与 parentRefs 正确
     - `dependsOn` 指向真实对象
</process>

<common_patterns>
<pattern name="basic-ks-yaml">
```yaml
---
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
</pattern>

<pattern name="basic-kustomization-yaml">
```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrelease.yaml
  - ./externalsecret.yaml
```
```
把第二项保留在真正存在 `externalsecret.yaml` 的场景。
</pattern>

<pattern name="configmap-generator">
```yaml
configMapGenerator:
  - name: <app-name>-config
    files:
      - config.yaml=./resources/config.yaml
generatorOptions:
  disableNameSuffixHash: true
```
</pattern>

<pattern name="envfrom-secret">
```yaml
envFrom:
  - secretRef:
      name: <app-name>-secret
```
</pattern>
</common_patterns>

<anti_patterns>
<pitfall name="unnecessary-config">
不要为了“看起来完整”补字段。配置完整度来自必要性，不来自字段数量。
</pitfall>

<pitfall name="unauthorized-labels">
不要擅自添加标签。`labels:` 只在当前仓库已有明确用途且当前服务真实需要时写。

本次明确记录的反例：

```yaml
labels:
  app.ooooo.space/need-main-pg: "true"
```

这个标签只有在当前服务确实需要该语义时才写。
</pitfall>

<pitfall name="unauthorized-merge-policy">
不要擅自写：

```yaml
mergePolicy: Merge
```

只有当当前资源生成方式明确需要它，并且仓库里已有同类依据时才出现。
</pitfall>

<pitfall name="copy-template-blindly">
不要把参考目录整块复制过来。要按当前服务逐项删减。
</pitfall>

<pitfall name="fake-dependencies">
不要把 `cilium`、`azure-store`、`volsync`、`cloudnative-pg-cluster`、`dragonfly-cluster` 全写上。每个依赖都要能说清用途。
</pitfall>

<pitfall name="unused-files">
不要预先创建 `externalsecret.yaml`、`resources/`、PVC、额外 route。当前服务用到再写。
</pitfall>
</anti_patterns>

<validation>
逐项检查：

- 目录是否仍然是两层结构。
- `ks.yaml` 的 `path` 是否指向 `./k8s/apps/common/<app-name>/app`。
- `kustomization.yaml` 是否只引用真实存在的文件。
- `HelmRelease` 是否只包含当前服务必要字段。
- `labels`、`mergePolicy`、`components`、`dependsOn` 是否都有明确理由。
- `ExternalSecret` 是否只暴露当前服务实际消费的键。
- staging 入口渲染是否通过。
</validation>

<reference_guides>
优先参考这些目录：

- 简单服务：`k8s/apps/common/echo/`
- 带密钥服务：`k8s/apps/common/vaultwarden/`
- 带数据库服务：`k8s/apps/common/affine/`
- 带配置文件生成：`k8s/apps/common/cli-proxy-api/`
- 带 init-db：`k8s/apps/common/memos/`、`k8s/apps/common/shlink/`

同时遵循项目目录约定：`.agents/skills/home-ops-conventions/SKILL.md`
</reference_guides>

<success_criteria>
这个技能使用成功时，产出的应用满足这些条件：

- 文件放置位置符合 `home-ops` 目录习惯。
- `ks.yaml`、`app/` 资源结构完整。
- 每个依赖、标签、字段都有明确用途。
- 没有为了模板完整度额外写入无关配置。
- `kustomize build` 在 app、common、staging 三层都能通过。
</success_criteria>
