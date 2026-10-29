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

1. 找 1 到 3 个最接近的现有目录当模板
2. 创建上述目录结构，只写当前服务真正需要的文件
3. 注册到对应当层的 `kustomization.yaml`
4. `kustomize build` 验证 app、对应中间层与 staging 三层

## Workflows

### 0. 设计（可选）

复杂服务先写设计文档到 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`，提交后等用户审查。审查通过再写代码。

对于需求尚不明确的服务，先逐条澄清需求、边界与验收再写代码。

### 1. 创建代码

1. **识别形态与归属**：先判断服务属于 apps 还是 infra：
   - 普通应用 → `k8s/apps/common/<app>/`
   - 基础设施（网络、存储、监控等）→ `k8s/infra/common/<category>/<app>/`
   - 外部入口（如 caddy-external、ss-rust）→ `k8s/infra/common/network/external/<app>/`

   判断服务技术特征（HTTP、DB、密钥、持久化、Route），选择最贴近的参考目录
2. **编写 `ks.yaml`**：`dependsOn` 只写真实前置，`components` 只写用到的能力
3. **编写 `helmrelease.yaml`**：优先使用 app-template，镜像、环境变量、Service、Route、持久化、探针与资源按需补齐
4. **编写 `kustomization.yaml`**：只引用真实存在的文件，需生成 ConfigMap 时配置 `configMapGenerator`
5. **编写 `externalsecret.yaml`**：按下文「Secret 注入决策」确认模式，`store` 固定为 `bitwarden-store`，`dataFrom.extract.key` 使用真实 BWS secret 名（BWS 忽略 `property` 且不支持 `dataFrom.find`，详见 `docs/6-secrets.md`），`target.template.data` 仅暴露实际消费的键
6. **写入 BWS**：使用 `task secret:set-key` 写入（依赖 `BWS_ACCESS_TOKEN`），`task secret:keys` 验证，禁止读取 secret 原文
7. **注册**：加入对应层级 `kustomization.yaml` 并沿用该文件现有排序风格：
   - apps 服务 → `k8s/apps/common/kustomization.yaml`
   - infra 服务 → 对应 category 层，如 `k8s/infra/common/network/external/kustomization.yaml`
8. **验证**：执行三层 `kustomize build`：
   - apps: `app/` → `k8s/apps/common/` → `k8s/apps/staging/`
   - infra: `app/` → `<category>/` → `k8s/infra/staging/`

### 2. 提交审查

代码编写完成后停在工作区，等用户审查同意再提交并提 PR

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
  ├── infra.yml  (Flux Kustomization, wait: false)
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

Pod 未就绪时检查 Pod Events 与容器日志定位问题

## Secret 注入决策

引入新服务时，根据服务消费 secret 的方式从三种模式中选一种：

```
新服务来了
│
├─ 1. 是不是公共值（多服务共享、极少变）？
│     ├─ MAIN_DOMAIN / CLOUDFLARE_TUNNEL_ID 等 → SOPS cluster-secrets
│     │    Flux 已自动通过 postBuild.substituteFrom 注入所有子 Kustomization
│     │    直接写 ${MAIN_DOMAIN} 即可
│     └─ 服务私有 secret → 下一步
│
├─ 2. 服务只认 env var（如 karakeep）
│     └─ ExternalSecret + envFrom
│         ES 映射 key → 整包注入容器，服务工作不涉及配置
│
├─ 3. 服务要配置文件
│     ├─ 3a. 配置文件支持运行时 ${ENV_VAR}（如 go2rtc）
│     │    ├─ ConfigMap 存纯文本配置（git 版本管理）
│     │    ├─ ExternalSecret 只给 env var
│     │    ├─ 容器同时挂载 ConfigMap + envFrom Secret
│     │    └─ 运行时自解析 ${} → 优先选这种
│     │
│     ├─ 3b. 不支持运行时 ${}，但配置量大/结构复杂
│     │    └─ ExternalSecret + templateFrom.configMap（如 cli-proxy-api）
│     │        ConfigMap 模板含 {{ .xxx }} 占位符
│     │        ES 引擎渲染后写入最终 Secret
│     │        配置结构在 git 可追溯
│     │
│     └─ 3c. 配置小、和 secret 紧耦合
│           └─ ExternalSecret 内联模板（如 immich）
│               配置直接写在 ES 的 template.data 里
│               非敏感配置变更也需摸 BWS
│
└─ 4. 两种都行 → 优先 env var。env 太多（>10 个）退 3a/3b
```

### 关键细节

- **Flux postBuild.substitute 与配置文件 `${}` 冲突**：当配置文件的 `${ENV_VAR}` 被 Flux 提前替换时，采用以下两种解法：
  - **`kustomize.toolkit.fluxcd.io/substitute: disabled`**：资源级排除，Flux 只跳过带该注解的资源。配置文件走 ConfigMap 时写在 `kustomization.yaml` 的 `generatorOptions.annotations` 上（如 gatus、go2rtc、caddy-external），其余资源的 `${VAR}` 照常替换
  - **`$$` 转义**：在 YAML 值里用 `$${VAR}`，kustomize 输出时转成 `${VAR}`，运行时程序自己解析。不影响 Kustomization 其他 `${VAR}` 的替换。该 Kustomization 仍需消费 `${TIMEZONE}` 等变量时优先采用此方式（如 crowdsec、ss-rust）
  需要整个 Kustomization 都跳过 postBuild 变量时，在 ks.yaml 的 metadata.labels 添加 `substitution.flux/disabled: "true"`，集群层 patch 按该标签跳过变量注入（见 `docs/ARCHITECTURE.md` §8）
- **多个 ExternalSecret 写入同一目标 Secret**：使用单一 ExternalSecret 合并多个 `extract`（如 authelia 同时 extract `authelia`、`mail` 与 `cloudnative-pg`）
- **Bootstrap 阶段的 azure:// 占位符**：仅保留 `azure-creds` 用于集群初次引导，普通服务密钥一律写入 BWS

## Anti-patterns

- 保持字段极简，只写有明确用途的配置
- 声明真实存在的依赖与组件
- 仅创建当前必需的文件
- 参考现有目录时逐项按需提取，不盲目全盘复制
- 仅在存在规范约束时添加标签与策略
## Validation

- 目录是否保持两层结构（`ks.yaml` → `app/`）
- `path` 是否指向正确（apps 指向 `./k8s/apps/common/<app>/app`，infra 指向 `./k8s/infra/common/<category>/<app>/app`）
- `kustomization.yaml` 是否只引用真实存在的文件
- 字段、依赖与标签是否具备明确依据
- 注册层与 staging 渲染是否通过

## Reference

- 模式库与 YAML 示例：See [REFERENCE.md](REFERENCE.md)
- 目录规范：`CODING_STANDARDS.md` 的「目录与模块归属」「集群外资产」
