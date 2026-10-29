# Kopiur 备份

集群卷备份使用 [Kopiur](https://github.com/home-operations/kopiur) + Kopia：

- 本地仓库 `sakamoto`：集群外 MinIO 的 `kopiur` 桶，每小时一次，供细粒度回滚
- 云端仓库 `cloud-openlist`：集群内 OpenList S3 的 `kopia` 桶 `kopiur/` 前缀，作为异地副本。由集群级 `SnapshotReplication` 每天把本地仓库的最新快照复制过去，应用侧不再直写云端

取舍见 [ADR-0006](adr/0006-kopiur-cloud-daily-repository.md)

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

组件自动创建：PVC（`IfNotPresent` 保护已有卷）、本地 SnapshotPolicy + SnapshotSchedule（`H * * * *`，按对象错峰）、Restore CR。组件的 postBuild 变量只作用于本地仓库

## 云端异地副本

异地副本不在应用组件里声明。集群级声明在 `k8s/infra/common/kopiur-system/kopiur/repository-cloud/snapshotreplication.yaml`，一个 `SnapshotReplication` 覆盖所有应用：

- 源 `sakamoto` → 目标 `cloud-openlist`；复制的是快照清单与它引用的内容（`kopia snapshot migrate`），不是仓库 blob 镜像
- `schedule.cron: 15 4 * * *` + `jitter: 10m`。时区不显式声明：复制调度按 `spec.schedule.timezone` → **源仓库** `scheduleDefaults.timezone`（`sakamoto` 为 `Asia/Shanghai`）→ UTC 的顺序解析，所以仍是本地低峰 04:15
- `selection.latestOnly: true`：每个身份只搬最新快照，因此天然每天一份，不复制小时级历史
- `migrate.throttle.destination.uploadBytesPerSecond: 3145728`（3 MiB/s）：避免复制挤占 OpenList 上行
- `pruning.retention`：只对**本复制对象创建的副本**做 GFS 保留（`keepDaily: 7`、`keepWeekly: 4`），不碰目标仓库里别人写入的快照

每个副本在 `kopiur-system` 生成一条 `Snapshot` CR，名字是 `sakamoto-to-cloud-copy-<id>-<hash>`，带 `kopiur.home-operations.com/origin=replicated` 与 `kopiur.home-operations.com/snapshot-replication=sakamoto-to-cloud` 标签，且**没有** ownerReference：删掉这个 CR，副本数据仍留在仓库里，只有 `spec.pruning` 或手工删除副本 CR 才会清理数据

改造前的 `${APP}-cloud` 直写快照不会被这次删除带走：旧 SnapshotSchedule 的 `deletion.onScheduleDelete` 默认 `Retain`，调度删除时只删 CR，kopia 快照留在目标仓库，随后由 catalog 接管为 `discovered`（其 `deletionPolicy` 固定 `Retain`）。这些旧副本不在本复制的 `pruning` 范围内（pruning 只认本复制创建的副本），会一直留着，需要时手工清理

手动触发一次复制：

```bash
task kopiur:replicate          # 装了 kubectl-kopiur 就 --wait 到结束
task kopiur:replicate WAIT=false
```

## 恢复

恢复由组件声明完成：PVC 的 `dataSourceRef` 指向同名 `Restore`，`Restore` 从 `fromPolicy` 指定的策略取最新快照。PVC 不存在时，Flux reconcile 重建 PVC，volume populator 自动填充数据。因此删除应用的 Kustomization 后由父级重新 reconcile，或在新集群上 bootstrap，都会自动恢复

`task kopiur:snapshots`、`task kopiur:status` 只用于查看；仓库迁移等少见操作用 `task kopia:*`。没有恢复用的 task

### 本地仓库不可用时切到云端

云端副本现在由 `SnapshotReplication` 生成，目标仓库里是带 `origin=replicated` 的副本，已经没有 `${APP}-cloud` 策略可切。步骤：

1. 找一个可用副本。`AT` 是快照时间；`USER`/`HOST`/`PATH` 就是下一步 `Restore.spec.source.identity` 要填的值：

```bash
kubectl -n kopiur-system get snapshot -l kopiur.home-operations.com/origin=replicated \
  -o custom-columns='NAME:.metadata.name,USER:.status.snapshot.identity.username,HOST:.status.snapshot.identity.hostname,PATH:.status.snapshot.identity.sourcePath,AT:.status.timing.startTime,PHASE:.status.phase'
```

2. 提交一次 Git，在该应用自己的 `ks.yaml` 里给它的 `Restore` 打补丁：数据源指向云端仓库，并把 `onMissingSnapshot` 从组件的 `Continue` 改成 `Fail`，否则身份没匹配上时会安静地建出空卷。以 qui 为例：

```yaml
  patches:
    - target:
        kind: Restore
        name: qui
      patch: |
        - op: add
          path: /spec/repository
          value:
            kind: ClusterRepository
            name: cloud-openlist
        - op: replace
          path: /spec/source
          value:
            identity:
              username: <USER>
              hostname: <HOST>
              sourcePath: <PATH>   # 通常是 /pvc/<app>
        - op: replace
          path: /spec/policy/onMissingSnapshot
          value: Fail
```

`source.identity` 直接给原始 kopia 身份，没有对象可推导仓库，所以必须显式给 `spec.repository`；这也是它与 `fromPolicy` 的关键差别

3. 同一提交里把 `k8s/infra/common/kopiur-system/kopiur/ks.yaml` 中 `kopiur-repository` 的 `wait: true` 改成 `false`，让应用的 Kustomization 不再因本地仓库 NotReady 而停止 reconcile
4. 只有 PVC 被重建的应用会真正恢复；本地仓库恢复后 revert 该提交

2026-10-22 已用 qui 演练：当时云端副本由应用的 `${APP}-cloud` 策略直写，删掉 qui 的 Kustomization 后从云端快照恢复成功，文件与快照一致。改成 `SnapshotReplication` 副本后的这条路径未演练；演练时本地仓库正常，第 3 步未实测

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

云端仓库（异地副本，全部在 `kopiur-system`）：

```bash
kubectl -n kopiur-system get snapshot -l kopiur.home-operations.com/origin=replicated \
  -o custom-columns='NAME:.metadata.name,USER:.status.snapshot.identity.username,HOST:.status.snapshot.identity.hostname,PATH:.status.snapshot.identity.sourcePath,AT:.status.timing.startTime,PHASE:.status.phase'
```

复制对象本身：

```bash
kubectl -n kopiur-system get snapshotreplication sakamoto-to-cloud \
  -o custom-columns='SOURCE:.spec.sourceRef.name,DEST:.spec.destinationRef.name,SCHEDULE:.spec.schedule.cron,PHASE:.status.phase,LAST:.status.lastReplicated'
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
