# Kopiur 备份

集群卷备份使用 [Kopiur](https://github.com/home-operations/kopiur) + Kopia：

- 本地仓库 `sakamoto`：集群外 RustFS 的 `kopiur` 桶，每小时一次，供细粒度回滚
- 云端仓库 `cloud-openlist`：集群内 OpenList S3 的 `kopia` 桶 `kopiur/` 前缀，由集群级 SnapshotReplication 每天复制本地快照

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

集群级单一资源 `k8s/infra/common/kopiur-system/kopiur/repository-cloud/snapshotreplication.yaml`，源 `sakamoto`，目标 `cloud-openlist`。`task kopiur:replicate` 手动触发，绕过每日窗口，成功后顺延下一个自动窗口

## 恢复

恢复由组件声明完成：PVC 的 `dataSourceRef` 指向同名 `Restore`，`Restore` 从 `fromPolicy` 指定的策略取最新快照。PVC 不存在时，Flux reconcile 重建 PVC，volume populator 自动填充数据。因此删除应用的 Kustomization 后由父级重新 reconcile，或在新集群上 bootstrap，都会自动恢复

`task kopiur:snapshots`、`task kopiur:status` 只用于查看；仓库迁移等少见操作用 `task kopia:*`。没有恢复用的 task

### 本地仓库不可用时切到云端

没有 `${APP}-cloud` 策略可切。在该应用的 `ks.yaml` 里给 `Restore` 打补丁，数据源指向 `cloud-openlist`：`source.identity` 用 `应用名@命名空间:/pvc/应用名`，并显式给 `spec.repository`；`policy.onMissingSnapshot` 改 `Fail`，否则身份没匹配上会建出空卷；选择器只按 `kind: Restore` 写，Flux 先构建后替换 `${APP}`，按 `name` 选不中

同时把 `kopiur-repository` 的 `wait` 改成 `false`，本地仓库恢复后 revert

~~2026-10-22 用 qui 演练从云端恢复成功~~ 切的是已删除的 `${APP}-cloud` 策略，新路径未演练

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
kubectl -n kopiur-system get snapshot -l kopiur.home-operations.com/origin=replicated
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
