# Kopiur 备份

集群卷备份使用 [Kopiur](https://github.com/home-operations/kopiur) + Kopia，同时写入两个仓库：

- `sakamoto`：集群外 MinIO (`s3://kopiur`)，每小时，供本地细粒度回滚
- `cloud-openlist`：集群内 OpenList S3 (`s3://kopia/kopiur/`)，每天一次，供异地容灾

两套调度由同一个备份组件生成，见 [ADR-0005](adr/0005-kopiur-dual-repository.md)

依赖：

- Longhorn（服务数据存储）
- `kopiur-system`（控制器 + ClusterRepository + Kopia WebUI）

## 添加新应用

在应用的 `ks.yaml` 引入备份组件，唯一必填变量是 `APP`：

```yaml
spec:
  components:
    - ../../../../components/kopiur/backup
  dependsOn:
    - name: kopiur-repository
      namespace: kopiur-system
  postBuild:
    substitute:
      APP: my-app
      KOPIUR_CAPACITY: 2Gi
```

其余 `KOPIUR_*` 变量及其默认值定义在 `k8s/components/kopiur/backup/` 的模板中，按需覆盖缓存容量、存储类、快照类或运行用户。组件自动创建 PVC（`IfNotPresent` 保护已有卷）、本地与云端两套 SnapshotPolicy 与 SnapshotSchedule，以及 Restore CR

云端策略默认 `H 4 * * *`、保留 7 天。云端只保留每日快照，避免小时级 SQLite 碎片包在云端触发小包合并后的全量重传，细粒度回滚由本地 `sakamoto` 仓库承担

## 恢复

```bash
task kopiur:restore APP=<app> CONFIRM=<app> NAMESPACE=<ns>
```

默认使用本地 `sakamoto` 仓库。本地 MinIO 或宿主机不可用时，把组件生成的 `Restore` 中 `spec.source.fromPolicy.name` 改为 `${APP}-cloud`，即从 OpenList 直接恢复，恢复完成后改回

`task kopiur:restore` 用于本地仓库恢复。灾难场景下本地仓库本身不可用，需先修正 `Restore` 的来源，再按该任务的步骤手工执行删除 PVC、重建 Kustomization 与等待 Bound

详见 `kopiur-restore` skill

## 查看快照

```bash
task kopiur:snapshots           # 全量
task kopiur:snapshots APP=plex  # 按应用过滤
```

或访问 Kopia WebUI：`https://kopia.<DOMAIN>`

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
