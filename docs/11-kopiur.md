# Kopiur 备份

集群卷备份使用 [Kopiur](https://github.com/home-operations/kopiur) + Kopia：

- 本地仓库 `sakamoto`：集群外 MinIO 的 `kopiur` 桶，每小时一次，供细粒度回滚
- 云端仓库 `cloud-openlist`：集群内 OpenList S3 的 `kopia` 桶 `kopiur/` 前缀，作为云端副本，由集群级 SnapshotReplication 每天复制本地仓库的最新快照过去

取舍见 [ADR-0008](adr/0008-kopiur-cloud-snapshotreplication.md)

依赖：
- Longhorn（服务数据存储）
- `kopiur-system`（控制器 + ClusterRepository + Kopia WebUI）

## 添加新应用

在 `ks.yaml` 引入 kopiur backup 组件，并补全 `postBuild` 变量：

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app my-app
  namespace: &namespace default
spec:
  components:
    - ../../../../components/kopiur/backup
  dependsOn:
    - name: kopiur-repository
      namespace: kopiur-system
  postBuild:
    substitute:
      APP: *app
      KOPIUR_CAPACITY: 2Gi
      # KOPIUR_CACHE_CAPACITY: 5Gi
      # KOPIUR_ACCESSMODES: ReadWriteOnce
      # KOPIUR_STORAGECLASS: longhorn
      # KOPIUR_STAGING_STORAGECLASS: longhorn-snapshot  # 暂存克隆卷，须与源卷同一 CSI driver
      # KOPIUR_SNAPSHOTCLASS: longhorn-snapclass
      # 若应用以非 1000 用户运行：
      # KOPIUR_PUID: "0"
      # KOPIUR_PGID: "0"
```

组件自动创建：PVC（`IfNotPresent` 保护已有卷）、本地 SnapshotPolicy 与 SnapshotSchedule（`H * * * *`，按对象错峰）、Restore CR

## 云端副本

不在应用组件里声明，集群级单一资源 `k8s/infra/common/kopiur-system/kopiur/repository-cloud/snapshotreplication.yaml`，源是 `sakamoto`，目标是 `cloud-openlist`。复制只搬快照清单与它引用的内容，不产生卷快照与暂存克隆

- 手动触发用 `task kopiur:replicate`。它直接给该资源打 `run-requested` 注解，绕过每日 04:15 的窗口；一次成功的手动复制会顺延下一个自动窗口，槽位由 `status.lastReplicated` 决定
- 改造前的 `${APP}-cloud` 直写快照不会被删除，也不在本复制 `pruning` 的范围内，会一直留着：旧 SnapshotSchedule 的 `deletion.onScheduleDelete` 默认 `Retain`，调度删除只删 Snapshot CR，kopia 快照留在目标仓库并由 catalog 接管为 `discovered`
- 副本 CR 的 `deletionPolicy` 是 `Delete`，删掉它就删掉目标仓库里对应的快照；删复制对象本身不会删数据

## 恢复

恢复由组件声明完成：PVC 的 `dataSourceRef` 指向同名 `Restore`，`Restore` 从 `fromPolicy` 指定的策略取最新快照。PVC 不存在时，Flux reconcile 重建 PVC，volume populator 自动填充数据。因此删除应用的 Kustomization 后由父级重新 reconcile，或在新集群上 bootstrap，都会自动恢复

`task kopiur:snapshots`、`task kopiur:status` 只用于查看；仓库迁移等少见操作用 `task kopia:*`。没有恢复用的 task

### 本地仓库不可用时切到云端

目标仓库里是带 `kopiur.home-operations.com/origin=replicated` 的副本，没有 `${APP}-cloud` 策略可切。把该应用的 `Restore` 数据源指向 `cloud-openlist`：

```yaml
  patches:
    - target: {kind: Restore}
      patch: |
        - op: add
          path: /spec/repository
          value: {kind: ClusterRepository, name: cloud-openlist}
        - op: replace
          path: /spec/source
          value:
            identity: {username: <应用名>, hostname: <命名空间>, sourcePath: /pvc/<应用名>}
        - op: replace
          path: /spec/policy/onMissingSnapshot
          value: Fail
```

- 选择器只按 `kind` 写。Flux 先跑 kustomize 构建，patch 在这一步生效，之后才替换 `${APP}`，所以按 `name` 选不中模板里的 Restore，patch 会静默跳过
- 身份默认是 `应用名@命名空间:/pvc/应用名`，也可以用「查看快照」的 `USER`、`HOST`、`PATH` 核对。`source.identity` 没有对象可推导仓库，所以要显式给 `spec.repository`
- `onMissingSnapshot` 必须改成 `Fail`，否则身份没匹配上时会安静地建出空卷
- 同时把 `kopiur-repository` 的 `wait` 改成 `false`，让应用不再等本地仓库；本地仓库恢复后 revert

~~2026-10-22 用 qui 演练从云端恢复成功~~ 当时切的是已删除的 `${APP}-cloud` 策略，这条路径随策略删除失效，新路径未演练

- 删除 Kustomization 不会删除备份：快照默认 `onScheduleDelete: Retain`，CR 被删后数据仍在仓库，随后由 catalog 接管为 `adopted` 快照
- 恢复会先停在 `MissingRecordedIdentity` 等待约 5 分钟，直到 catalog 接管云端快照后才拉取数据，期间不会产出空卷

OpenList 自身的云端副本要经 OpenList 读取。集群与 sakamoto 主机同时损坏时，只能临时用 VPS 上的 OpenList 读取云端仓库，前提是开放其 S3 端口 5246（当前只发布 5244）

## 查看快照

本地仓库：

```bash
task kopiur:snapshots           # 全量
task kopiur:snapshots APP=plex  # 按应用过滤
```

或访问 Kopia WebUI：`https://kopia.<DOMAIN>`，它同样只连接本地仓库

云端仓库（副本都在 `kopiur-system`）：

```bash
kubectl -n kopiur-system get snapshot -l kopiur.home-operations.com/origin=replicated \
  -o custom-columns='NAME:.metadata.name,USER:.status.snapshot.identity.username,HOST:.status.snapshot.identity.hostname,PATH:.status.snapshot.identity.sourcePath,AT:.status.timing.startTime'
```

复制对象本身：

```bash
kubectl -n kopiur-system get snapshotreplication
```

## 查看数据

```bash
task kube-run pvc=<app-name> namespace=<ns>
# 或
task browse-pvc namespace=<ns> claim=<app-name>
```

## 旧数据迁移

### 从 VPS/外部 kopia 仓库迁移

```bash
# 列出 sakamoto 上的快照
task kopia:list

# 拉取 → 推送
SNAPSHOT_ID=xxx task kopia:full
```

### 从旧 kopia-backup 桶冷迁移

```bash
# 活跃服务基线迁移
task kopia:migrate-active

# 未启用服务最后快照迁移
task kopia:migrate-inactive
```
