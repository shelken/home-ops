# VolSync → kopiur 单 app 试点迁移调研

**日期**: 2026-07-26
**范围**: 只研究，不实现
**已拍板**: ① 新桶冷启动（不复用 `kopia-backup` 历史） ② 先单 app 试点 ③ 接受 alpha 风险

---

## 结论（先行）

| 项 | 结论 |
| --- | --- |
| 是否可试点 | **可以**。集群 k3s `v1.36.1` 满足 chart `kubeVersion >=1.32`；CSI snapshot、`longhorn-snapclass`、`longhorn-cache`/`longhorn-snapshot` 均已就绪。 |
| 推荐试点 app | **`qui`**（1Gi、live RS 成功、非核心、单 PVC） |
| 仓库策略 | **新建 MinIO 桶**（建议名 `kopiur`）+ 新 `ClusterRepository`；**不要**用 `kubectl kopiur migrate volsync --resolve-secrets` 的默认「原地 adopt `kopia-backup`」路径。 |
| 与现网共存 | 试点期间 **保留** `volsync-system` 与其余 app 的 VolSync；仅试点 app 去掉 `components/volsync`。 |
| 最大风险 | alpha CRD churn（0.7→0.8 已有 breaking）、CSI/Longhorn 并发尖峰（历史事故 007）、删除 Snapshot CR 可能连带删 kopia 快照（`deletionPolicy` 语义）。 |
| 现在不要做 | 全量切换、卸载 VolSync、双写同一 kopia 桶、在生产 app 上首试、依赖 README 过时的 `Backup*` kind 名。 |

---

## A. 架构对照

### A.1 对象模型

| 关注点 | VolSync（本仓：perfectra1n fork + kopia mover） | kopiur `v1alpha1`（0.8.x） |
| --- | --- | --- |
| 仓库 | **不是** K8s 对象；每 app 一个 Secret（`KOPIA_REPOSITORY`/`KOPIA_*`） | **`Repository`**（ns）/ **`ClusterRepository`**（cluster）一等公民 |
| 备份配方 | `ReplicationSource.spec.kopia`（PVC、retain、cache、copyMethod 揉在一起） | **`SnapshotPolicy`**（recipe，幂等，自身不触发） |
| 一次备份 | 内部 Job；无独立 CR | **`Snapshot`**（一次 kopia snapshot = 一个 CR，catalog + lifecycle） |
| 调度 | `spec.trigger.schedule` 写在 Source 上 | **`SnapshotSchedule`**（cron / `H` / jitter / timezone / `runOnCreate`） |
| 恢复 | `ReplicationDestination` + PVC `dataSourceRef` | **`Restore`** + PVC `dataSourceRef`（populator） |
| 维护 | 独立 `KopiaMaintenance` CR（fork） | **`Maintenance`**（默认可由 repo 托管；勿与 fork 的 KM 并存） |
| 额外 | — | **`RepositoryReplication`**（repo 间复制，试点不需要） |

**重要命名变更（ADR-0004）**：早期文档/README 表头仍写 `BackupConfig`/`Backup`/`BackupSchedule`；**当前落地 kind 是** `SnapshotPolicy` / `Snapshot` / `SnapshotSchedule`。
来源：

- <https://github.com/home-operations/kopiur/blob/main/README.md>
- <https://github.com/home-operations/kopiur/blob/main/docs/adr/0003-kopiur-rust-operator.md>
- <https://github.com/home-operations/kopiur/blob/main/docs/adr/0004-breaking-crd-and-field-renames.md>
- 本仓: `k8s/components/volsync/local/replicationsource.yaml`

### A.2 调度（含 H cron）

| | VolSync（本仓） | kopiur |
| --- | --- | --- |
| 现状 cron | **全部** live RS 为 `0 * * * *`（整点齐射） | 支持 Jenkins 式 **`H`**、`jitter`、timezone、`runOnCreate: false`（GitOps 友好，默认不立刻跑） |
| 锚点 | 易受 last-completion 漂移影响（ADR 批评点 G4） | wall-clock `cron(now)` |
| 与本仓事故关系 | 整点齐射压垮 Longhorn/控制面：`postmortems/007-volsync-burst-overloads-longhorn-control-plane.md` | 试点应直接用 `H * * * *` + jitter，**不要**复制 `0 * * * *` |

示例（官方）: `deploy/examples/01-single-pvc-scheduled.yaml`
上游 onedr0p 落地: `kubernetes/components/kopiur/backup/snapshotschedule.yaml` → `cron: H * * * *`

### A.3 仓库模型

- **VolSync 本仓**: 所有 app 写同一 S3 桶 `s3://kopia-backup`，endpoint `sakamoto.lan:9000`，TLS 关闭；凭据来自 AKV `volsync-template`（`azure-store`）。
  路径: `k8s/components/volsync/local/externalsecret.yaml`、`k8s/infra/common/volsync-system/kopia/app/externalsecret.yaml`
- **kopiur**: 一个 `ClusterRepository` 可被多 ns 引用；`allowedNamespaces` 门禁；identity 用 CEL（`hostnameExpr`/`usernameExpr`）；maintenance 默认可托管。
  官方例: `deploy/examples/02-cluster-repository.yaml`
  onedr0p: `kubernetes/apps/kopiur-system/kopiur/repository/clusterrepository.yaml`（桶 `kopiur`，Garage S3）

**用户拍板 = 新桶冷启动** ⇒ 与 CLI 默认 kopia-migrate「原地 adopt」**相反**：新桶、新 repo、历史从 0 开始；旧 `kopia-backup` 继续只给 VolSync 用，直到全量迁移决策。

### A.4 Restore 路径

| | VolSync | kopiur |
| --- | --- | --- |
| GitOps 首次部署 | PVC `dataSourceRef` → `ReplicationDestination`（`manual: restore-once`） | PVC `dataSourceRef` → `Restore`（`fromPolicy` + `onMissingSnapshot: Continue`） |
| 本仓模板 | `k8s/components/volsync/pvc.yaml` + `local/replicationdestination.yaml` | onedr0p: `components/kopiur/backup/{pvc,restore}.yaml` |
| 选择快照 | 主要靠 identity + latest | `snapshotRef` / `fromPolicy.offset` / identity / point-in-time（例 03/13/14） |
| 空仓行为 | 历史上易静默空 PVC（G7） | 默认更严格；deploy-or-restore 需显式 `onMissingSnapshot: Continue` |

### A.5 G1–G21 与本环境对照（摘要）

来源: ADR-0003 §1.1 <https://github.com/home-operations/kopiur/blob/main/docs/adr/0003-kopiur-rust-operator.md>

| Gap | 含义 | 本环境是否痛 | 试点是否立刻受益 |
| --- | --- | --- | --- |
| G1 | Repo 非 K8s 资源 | 是（每 app Secret 重复） | 是（一个 ClusterRepository） |
| G2 | 1 RS = 1 PVC | 中（多数单 PVC） | 低 |
| G3 | apply 立即备份 | 中 | 是（`runOnCreate: false`） |
| G4 | 无 H/jitter/tz | **高**（007 事故） | **高** |
| G5–G6 | 锁/堆积/重试 | 中 | 中 |
| G7–G10 | restore UX / populator | 恢复流程依赖时高 | 试点验证 restore 时高 |
| G11 | maintenance 归属 | 有独立 `KopiaMaintenance` | 新桶由 kopiur 自管即可 |
| G17 | 触发与配方耦合 | 中 | 可 `kubectl kopiur snapshot now` |
| G20 | 删 Source 不删快照 | 是 | **反向风险**：删 Snapshot CR 默认可删 repo 内快照 |
| G19 | VolSync 不再扩 mover | 已用 fork | 战略动机 |

### A.6 上游 onedr0p 实际落地形态

本地克隆: `/Users/shelken/Code/kaiyuan/homelab/home-ops`（即 home-operations/home-ops）

| 路径 | 作用 | 关键字段 |
| --- | --- | --- |
| `kubernetes/apps/kopiur-system/namespace.yaml` | ns | — |
| `kubernetes/apps/kopiur-system/kopiur/app/helmrelease.yaml` | 装 operator | monitoring dashboards/PrometheusRule/ServiceMonitor；pod SC 1000；memory limit 2Gi |
| `kubernetes/apps/kopiur-system/kopiur/app/ocirepository.yaml` | OCI chart | `ghcr.io/home-operations/charts/kopiur`（现网 0.8.1） |
| `kubernetes/apps/kopiur-system/kopiur/repository/clusterrepository.yaml` | 共享仓 | `backend.s3.bucket: kopiur`，`endpoint: expanse.internal:9000`，`tls.disableTls: true`，`allowedNamespaces.all: true`，secret 在 `kopiur-system` |
| `kubernetes/apps/kopiur-system/kopiur/ks.yaml` | Flux：app 与 repository 两段 KS | repository `dependsOn: kopiur` |
| `kubernetes/components/kopiur/backup/*.yaml` | app 组件 | `SnapshotPolicy` + `SnapshotSchedule` + `Restore` + PVC populator |
| `kubernetes/components/kopiur/secret/externalsecret.yaml` | 1Password → `kopiur-repository-secret` | `KOPIA_PASSWORD` + `AWS_*` |
| app 引用例 | `kubernetes/apps/default/qui/ks.yaml` | `components: [kopiur/backup]`，`APP: qui`；**无 volsync** |

SnapshotPolicy 关键字段（onedr0p）:

```yaml
spec:
  compression: { compressor: zstd }
  mover:
    cache: { capacity: ${KOPIUR_CAPACITY:=5Gi}, mode: Persistent, storageClassName: miroir-slow }
    securityContext: { runAsUser: ${KOPIUR_PUID:=1000}, runAsGroup: ${KOPIUR_PGID:=1000} }
  repository: { kind: ClusterRepository, name: expanse }
  retention: { keepLatest: 3, keepHourly: 24, keepDaily: 7, keepWeekly: 4 }
  sources: [{ pvc: { name: ${APP} } }]
  volumeSnapshotClassName: ${KOPIUR_SNAPSHOTCLASS:=csi-ceph-blockpool}
```

本仓对应替换建议: cache SC → `longhorn-cache`；snapshot class → `longhorn-snapclass`；data SC → `longhorn` / staging `longhorn-snapshot`。

**VolSync 在 onedr0p**: 本地克隆的 `kubernetes/` 下 **已无 volsync 组件**（已全量切走）。

---

## B. 本环境适配

### B.1 S3 / MinIO 现状与新桶需求

| 项 | 现状 | 新桶试点需要 |
| --- | --- | --- |
| 服务位置 | sakamoto Docker Compose MinIO | 同一 MinIO 实例即可 |
| 路径 | `compose/sakamoto/docker-compose.yml`（端口 9000） | — |
| 现桶 | `kopia-backup` | **新建**例如 `kopiur`（勿复用） |
| Endpoint（集群内） | `sakamoto.lan:9000` | 保持 |
| TLS | `doNotUseTLS` / `KOPIA_S3_DISABLE_TLS: "true"` | `backend.s3.tls.disableTls: true` |
| 凭据 | AKV `volsync-template` → `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `KOPIA_PASSWORD` | 新建 AKV 条目（建议 key 名 `kopiur`）或扩展策略；**密码可新可旧**（新桶 = 新 repo，与密码是否相同无关，但勿与旧桶双写） |
| 权限 | 现用户绑 `kopia-backup` | **必须**给新桶 `s3:*`（参考 `docs/13-minio.md` 的 policy 模板） |
| prefix | 现为桶根 | 可 `prefix: ""` 或 `pilot/`；冷启动无历史可空 |

ClusterRepository 形态（映射自 onedr0p + 本 endpoint）:

```yaml
# 示意 — 非落地文件
apiVersion: kopiur.home-operations.com/v1alpha1
kind: ClusterRepository
metadata:
  name: local-minio   # 名称自定
spec:
  allowedNamespaces:
    list: [default]   # 试点先收紧；全量再 all:true
  backend:
    s3:
      bucket: kopiur
      endpoint: sakamoto.lan:9000
      region: us-east-1
      tls: { disableTls: true }
      auth:
        secretRef:
          name: kopiur-repository-secret
          namespace: kopiur-system
  encryption:
    passwordSecretRef:
      name: kopiur-repository-secret
      namespace: kopiur-system
      key: KOPIA_PASSWORD
  # create: 新桶需允许初始化（以当版 CRD 字段为准；例 01 用 create.enabled: true）
```

### B.2 Longhorn / CSI snapshot / cache SC

| 资源 | 状态（2026-07-26 集群实测） | 来源 |
| --- | --- | --- |
| k8s | server `v1.36.1+k3s1` | `kubectl version` |
| `VolumeSnapshotClass/longhorn-snapclass` | Ready，driver `driver.longhorn.io`，**default** | `k8s/infra/common/kube-system/snapshot-controller/app/helmrelease.yaml` |
| SC `longhorn` | default，app PVC | longhorn |
| SC `longhorn-snapshot` | 1 replica，staging/mover | `k8s/infra/common/longhorn-system/longhorn/storageclass/snapshot.yaml` |
| SC `longhorn-cache` | 2 replica，kopia cache | 同上 |
| snapshot-controller | 已装 | `k8s/infra/common/kube-system/snapshot-controller/` |

kopiur 默认 `copyMethod: Snapshot`（例 21）；**不需要**为试点改 Longhorn。注意与现网 VolSync 同时做 CSI 快照会叠加控制面压力（见 C）。

### B.3 密钥映射：`azure-store` + `volsync-template` → ClusterRepository

| VolSync（现） | kopiur（建议） |
| --- | --- |
| `ClusterSecretStore/azure-store` | 不变 |
| AKV key `volsync-template` | **新建** AKV key `kopiur`（冷启动、权限边界清晰） |
| 每 app `ExternalSecret/${APP}-volsync` → `${APP}-volsync-secret` | **一份** ns=`kopiur-system` 的 `ExternalSecret` → `kopiur-repository-secret` |
| Secret keys: `AWS_*`, `KOPIA_PASSWORD`, `KOPIA_S3_ENDPOINT`, `KOPIA_REPOSITORY` | kopiur 只需要 Secret 内 **`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `KOPIA_PASSWORD`**；endpoint/bucket 写在 `ClusterRepository.spec.backend.s3`，**不**靠 env 拼 URL |
| 引用方式 | `auth.secretRef` + `encryption.passwordSecretRef`（**cluster-scoped 必须带 namespace**） |

参考:

- 本仓 ES: `k8s/components/volsync/local/externalsecret.yaml`
- onedr0p ES: `kubernetes/components/kopiur/secret/externalsecret.yaml`（1Password；本仓改 azure-store 即可）

### B.4 推荐试点 app

**唯一推荐: `qui`**

| 条件 | qui 证据 |
| --- | --- |
| 盘小 | PVC `1Gi`（live 中并列最小） |
| 非核心 | autobrr Web UI；挂了可暂缓，不影响路由/身份/媒体库 |
| live RS 成功 | `lastSyncTime=2026-07-26T07:15:07Z`，`WaitingForSchedule` |
| 单 PVC / 结构简单 | `k8s/apps/common/qui/ks.yaml` 仅 volsync 组件 + `VOLSYNC_CAPACITY: 1Gi` |
| 上游已有同名范例 | onedr0p `default/qui` 已用 `components/kopiur/backup` |

**不选**:

- `plex`/`jellyfin`（10Gi + 缓存，尖峰大）
- `home-assistant`/`frigate`（家庭自动化/录像，失败面大）
- `pocket-id`/`crowdsec`（安全面）
- `cli-proxy-api`（1Gi 且成功，但业务更关键；可作第二候选）
- `metatube`（2Gi 成功，但依赖 CNPG，同步时长 ~10m）

### B.5 声明了 volsync 但无 live RS 的 app

对照 `k8s/apps/common/kustomization.yaml`（注释 = 未启用）与 `kubectl get replicationsources -A`（2026-07-26）:

| App | Git 含 `components/volsync` | common kustomization 启用 | live RS |
| --- | --- | --- | --- |
| affine | 是 | 否（注释） | 无 |
| karakeep | 是 | 否 | 无 |
| n8n | 是 | 否 | 无 |
| new-api | 是 | 否 | 无 |
| ollama | 是 | 否 | 无 |
| qbittorrent | 是 | 否 | 无 |
| seafile | 是 | 否 | 无 |
| slash | 是 | 否 | 无 |
| vaultwarden | 是 | 否 | 无 |

**有 live RS（default）**: `cli-proxy-api`, `cpa-usage-keeper`, `frigate`, `home-assistant`, `jellyfin`, `metatube`, `openlist`, `plex`, `qui`
**有 live RS（security）**: `crowdsec`, `pocket-id`（`k8s/infra/common/security/*/ks.yaml`）

`icloudpd`: 仅 `dependsOn: volsync`，未见 component；无 RS。

---

## C. 阻塞与风险

### 硬（不做会直接失败/丢数据）

| ID | 风险 | 说明 | 缓解 |
| --- | --- | --- | --- |
| H1 | **双写同一 kopia 仓库** | 官方 migrate 对 fork-kopia 是 adopt；两套 operator 同仓并发 snapshot 会争 maintenance 锁/污染历史。用户已选新桶，**禁止**新 `ClusterRepository` 指向 `kopia-backup`。 | 新桶；试点 app **先停/删**其 VolSync RS 再启 kopiur schedule |
| H2 | **删 Snapshot CR 删快照** | G20 反转：默认 CR lifecycle 绑 kopia snapshot | 试点理解 `deletionPolicy`；全量前读 retention/cascade（0.8.0 breaking #272） |
| H3 | **MinIO 新桶权限** | 旧 policy 只绑 `kopia-backup` 则 Ready 失败 | 按 `docs/13-minio.md` 建桶+policy |
| H4 | **ClusterRepository Secret 无 namespace** | webhook 强制 cluster-scoped secretRef 带 ns | secret 固定 `kopiur-system` |
| H5 | **Helm/Flux 不自动升 CRD** | install.md 明确 upgrade 不更新 CRD | 升 0.8.x 时单独 apply CRD 流程 |

### 中（可试点，但要观察）

| ID | 风险 | 说明 | 缓解 |
| --- | --- | --- | --- |
| M1 | **alpha API churn** | 0.7.0 / 0.8.0 均有 BREAKING；kind 已从 Backup* 改名 | 钉 chart digest/tag；只试点 1 app；跟 CHANGELOG |
| M2 | **CSI + Longhorn 并发** | 007：多 RS 整点齐射拖垮控制面；kopiur 默认也走 VolumeSnapshot | 单 app + `H` cron + jitter；勿在整点再加齐射 |
| M3 | **fsGroup / PUID** | 008：fsgroup chown CPU 尖峰；本仓 mover 用 1000 | 对齐 app 的 PUID/PGID；参考 onedr0p mover SC |
| M4 | **监控缺口** | 现告警 `VolSyncVolumeOutOfSync` / `VolSyncComponentAbsent` 不覆盖 kopiur | 打开 chart `monitoring.prometheusRule` + ServiceMonitor（onedr0p 已开） |
| M5 | **与 VolSync privileged 注解并存** | ns 上有 `volsync.backube/privileged-movers=true`；kopiur 用 `kopiur.home-operations.com/privileged-movers` | 试点非 root 通常不需；需要时另 annotate |
| M6 | **identity 与旧历史** | 冷启动无历史则无关；若日后改 adopt 旧桶，必须钉 fork identity | 冷启动可默认 CEL identity |

### 软（体验/流程）

| ID | 风险 | 说明 |
| --- | --- | --- |
| S1 | README 与 CRD 名不一致 | 文档站/例为准，勿抄 README 表里旧 Backup* 名当唯一真相 |
| S2 | AGPL-3.0 chart/operator | 家用可接受；若有分发约束需自行评估 |
| S3 | 上游「勿提 PR」高速施工 | Issue 反馈；预期字段再变 |
| S4 | `migrate volsync` 对**新桶**策略不友好 | kopia 路径默认 adopt；应用 `--repository <新ClusterRepository>` 只做配置翻译，或手写组件（更贴 onedr0p） |
| S5 | 恢复演练成本 | 真删 PVC 风险高；可用临时 PVC + Restore 或 browse CLI |

---

## D. 试点最小变更面（只列路径/资源，不写代码）

### D.1 要新建的 GitOps 路径（建议，贴本仓 `infra/common` 习惯）

```
k8s/infra/common/kopiur-system/
  kustomization.yaml
  namespace.yaml                          # kopiur-system
  kopiur/
    ks.yaml                              # Flux KS: app + repository 两段
    app/
      kustomization.yaml
      ocirepository.yaml                 # oci://ghcr.io/home-operations/charts/kopiur 钉 0.8.1+
      helmrelease.yaml                   # monitoring on；对齐 onedr0p
    repository/
      kustomization.yaml
      clusterrepository.yaml             # 新桶
      externalsecret.yaml                # azure-store → kopiur-repository-secret
k8s/components/kopiur/
  backup/
    kustomization.yaml                   # Component
    snapshotpolicy.yaml
    snapshotschedule.yaml                # H * * * * + jitter
    restore.yaml                         # onMissingSnapshot: Continue
    pvc.yaml                             # dataSourceRef → Restore
  # secret 可放 system 级 repository/，不必 per-app
k8s/infra/common/kustomization.yaml      # 增加 kopiur-system 资源项
```

可选：`default` ns 增加 `kopiur.home-operations.com/privileged-movers`（仅当 mover 需要特权时）。

### D.2 试点 app（qui）改哪些

| 文件/资源 | 变更 |
| --- | --- |
| `k8s/apps/common/qui/ks.yaml` | `components/volsync` → `components/kopiur/backup`；`dependsOn` volsync → kopiur（repository Ready）；substitute `APP` + 容量/PUID 变量改名 |
| live：`ReplicationSource/qui`、`ReplicationDestination/qui-dst`、关联 volsync cache/dest PVC、`qui-volsync` ExternalSecret | **删除/停用**（避免同 PVC 双快照） |
| live PVC `qui` | **保留数据盘**；若组件强制带 populator PVC 模板，需确认与「已存在 PVC」模式兼容——**首迁建议：只加 SnapshotPolicy/Schedule，暂不替换已有 PVC 的 dataSourceRef**（restore 模板留给灾难恢复/新集群） |

> onedr0p 组件四件套适合**新集群 deploy-or-restore**。本仓 qui **已有数据 PVC**：试点最小集 = Policy + Schedule（+ 共享 ClusterRepository）。Restore/PVC 模板可进组件但 qui 首迁可不用。

### D.3 明确不动

- `k8s/infra/common/volsync-system/**`（整棵保留）
- 其余 app 的 `components/volsync`
- 桶 `kopia-backup` 与 AKV `volsync-template`
- Longhorn / snapshot-controller
- `KopiaMaintenance/daily`（仍服务旧仓；**不要**让它指向新桶）
- security 下 pocket-id/crowdsec

### D.4 验证清单（命令级成功标准）

**前置（仓外一次）**

```bash
# MinIO：建桶 + 授权（在 sakamoto 上，用现有 mc 流程，见 docs/13-minio.md）
mc mb s3/kopiur
# policy 绑到 kopiur 用户或复用可访问新桶的 key
```

**Operator**

```bash
kubectl -n kopiur-system rollout status deploy -l app.kubernetes.io/part-of=kopiur
kubectl get crd | grep kopiur.home-operations.com
# 期望 8 个：repositories, clusterrepositories, snapshotpolicies, snapshots,
# snapshotschedules, restores, maintenances, repositoryreplications
```

**仓库**

```bash
kubectl get clusterrepository -o wide
kubectl describe clusterrepository <name>   # Ready=True；无权限/TLS 错误
```

**试点备份**

```bash
kubectl -n default get snapshotpolicy,snapshotschedule
kubectl -n default get replicationsource qui     # 应 NotFound
# 手动触发一枪（若已装 CLI）
kubectl kopiur snapshot now -n default --policy qui --wait
kubectl -n default get snapshots
# 或等 H cron 后：
kubectl -n default get snapshots -l ...
```

**与旧仓隔离**

```bash
# 新桶对象数增加；旧桶 kopia-backup 无因 qui 停止而新增 qui 快照（可用 kopia UI/CLI 或 mc ls）
mc ls s3/kopiur
```

**可选 restore 冒烟（非破坏）**

```bash
# 临时 PVC + Restore 指到 qui 最新 snapshot；校验文件列表后删除临时资源
kubectl kopiur snapshots list -n default
# browse：kubectl kopiur browse ...
```

**回归**

```bash
kubectl get replicationsources -A   # 其余 app 仍有 lastSyncTime 刷新
kubectl get nodes                   # 无 lease 风暴
```

### D.5 回滚步骤

1. Flux：`qui/ks.yaml` 改回 `components/volsync` + `dependsOn: volsync`；推送/reconcile。
2. 确认 `ReplicationSource/qui` 恢复且 `lastSyncTime` 更新。
3. 删除 qui 的 `SnapshotSchedule`/`SnapshotPolicy`（注意 Snapshot `deletionPolicy`：若会删**新桶**快照，试点可接受；**绝不要**误指旧桶）。
4. 保留或删除 `kopiur-system` 均可：不影响其余 VolSync。
5. MinIO 新桶可留可删（冷启动无历史包袱）。

---

## E. 全量迁移前置条件（试点通过后才谈）

1. **试点稳定 ≥ 一个完整保留周期**（建议至少覆盖 `keepDaily` 窗口或 ≥7 天成功 Snapshot）。
2. **告警**：kopiur PrometheusRule 接入 Alertmanager；VolSync 规则在缩容时同步收缩。
3. **调度打散**：全量必须用 `H` + jitter，禁止回到全体 `0 * * * *`（007 教训）。
4. **CRD 升级手册**：Flux 升 chart 时如何 Apply CRD；锁定可接受的最小版本。
5. **Restore 演练**：至少一个非关键 app 完整 PVC 销毁→populator 恢复。
6. **密钥收敛**：每 app volsync Secret → 单一 `kopiur-repository-secret`；AKV 清理计划。
7. **Maintenance 单一主人**：退役 fork `KopiaMaintenance` 与 volsync maintenance；仅 kopiur Maintenance 管目标仓。
8. **旧桶策略**：`kopia-backup` 只读保留 N 天 / 导出 / 废弃——**另案**，因冷启动不自动继承。
9. **组件化**：`components/kopiur/backup` 变量集与现 `VOLSYNC_*` 对齐文档化。
10. **卸载 VolSync**：全部 app 切完且旧仓不再需要后，再动 `volsync-system`（最后一步）。

---

## F. 现在不要做

1. **不要**卸载或缩容 `volsync-system`。
2. **不要**把 `ClusterRepository` 指到 `kopia-backup` 并与 VolSync 并行写。
3. **不要**对所有 app 批量替换 component。
4. **不要**在 `plex`/`jellyfin`/`pocket-id`/`home-assistant` 上首试。
5. **不要**默认 `kubectl kopiur migrate volsync --resolve-secrets --apply`（会 adopt 旧仓；与拍板冲突）。若用 migrate，必须 `--repository <新仓名>` 且先停 RS。
6. **不要**复制整点 `0 * * * *` 到 SnapshotSchedule。
7. **不要**在未读 `deletionPolicy` 前批量删 Snapshot CR。
8. **不要**改业务 app 的存储类/Longhorn 全局参数「顺便优化」。
9. **不要**把研究结论当成已上线状态：集群在报告日后会变，实施前重跑 `kubectl get replicationsources/sc/volumesnapshotclass`。

---

## 附录

### 发布与版本（调研时点）

| 版本 | 日期 | 与迁移相关 |
| --- | --- | --- |
| 0.8.1 | 2026-07-24 | 当前最新；recovery-aware alerts、probe/Job 修复 |
| 0.8.0 | 2026-07-19 | **BREAKING**: SnapshotPolicy deletion cascade + auto-adoption；mass-deletion protection |
| 0.7.x | 2026-07 | multi-cluster shared repo、staging SC 覆盖、credential projection 等 |
| 0.7.0 | 2026-07-07 | **BREAKING** deps/controller 行为 |

来源: <https://github.com/home-operations/kopiur/blob/main/CHANGELOG.md>

### 一手源索引

| 源 | 位置 |
| --- | --- |
| kopiur 仓库 | <https://github.com/home-operations/kopiur> |
| 文档站 | <https://kopiur.home-operations.com/> |
| ADR-0003 G1–G21 | `docs/adr/0003-kopiur-rust-operator.md` |
| ADR-0004 改名 | `docs/adr/0004-breaking-crd-and-field-renames.md` |
| 例 01/02/21 | `deploy/examples/` |
| migrate 语义 | `docs/cli/migrate-volsync.md` |
| Chart | `deploy/helm/kopiur/`（`kubeVersion: ">=1.32.0-0"`，appVersion 0.8.1） |
| onedr0p 落地 | `/Users/shelken/Code/kaiyuan/homelab/home-ops/kubernetes/{apps/kopiur-system,components/kopiur}` |
| 本仓 VolSync | `k8s/components/volsync/`、`k8s/infra/common/volsync-system/` |
| 本仓事故 | `postmortems/001,007,008-volsync-*.md` |
| 本仓文档 | `docs/11-volsync.md`、`docs/13-minio.md` |

### 集群快照（写报告时）

```
ReplicationSources: default/{cli-proxy-api,cpa-usage-keeper,frigate,home-assistant,jellyfin,metatube,openlist,plex,qui}
                    security/{crowdsec,pocket-id}
全部 schedule: 0 * * * *
VolumeSnapshotClass: longhorn-snapclass (default)
SC: longhorn, longhorn-cache, longhorn-snapshot, longhorn-log, longhorn-static, openebs-hostpath, smb-app-storage
```

---

**报告结束。** 实施阶段应另开变更，并在动手前按 F.9 重验 live 状态。
