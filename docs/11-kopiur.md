# Kopiur 备份

集群卷备份使用 [Kopiur](https://github.com/home-operations/kopiur) + Kopia，同一个备份组件为每个应用生成两套策略：

- 本地仓库 `sakamoto`：集群外 MinIO 的 `kopiur` 桶，每小时一次，供细粒度回滚
- 云端仓库 `cloud-openlist`：集群内 OpenList S3 的 `kopia` 桶 `kopiur/` 前缀，每天一次，保留 7 天，作为异地副本

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

组件自动创建：PVC（`IfNotPresent` 保护已有卷）、本地与云端两套 SnapshotPolicy 和 SnapshotSchedule（本地 `H * * * *`，云端 `H 4 * * *`，均按对象错峰）、Restore CR。云端策略使用临时缓存卷，容量由 `KOPIUR_CLOUD_CACHE_CAPACITY` 覆盖

## 恢复

恢复由组件声明完成：PVC 的 `dataSourceRef` 指向同名 `Restore`，`Restore` 从 `fromPolicy` 指定的策略取最新快照。PVC 不存在时，Flux reconcile 重建 PVC，volume populator 自动填充数据。因此删除应用的 Kustomization 后由父级重新 reconcile，或在新集群上 bootstrap，都会自动恢复

`task kopiur:*` 是仓库迁移等少见操作用的工具，不是日常恢复入口

### 本地仓库不可用时切到云端

未演练，演练通过前只作为预案。提交一次 Git，改两行：

```diff
# k8s/components/kopiur/backup/restore.yaml
-      name: ${APP}
+      name: ${APP}-cloud
# k8s/infra/common/kopiur-system/kopiur/ks.yaml（kopiur-repository）
-  wait: true
+  wait: false
```

- 第一行让所有 `Restore` 改从云端策略取快照，只有 PVC 被重建的应用会真正恢复
- 第二行让应用的 Kustomization 不再因本地仓库 NotReady 而停止 reconcile
- 本地仓库恢复后 revert 该提交

OpenList 自身的云端副本要经 OpenList 读取。集群与 sakamoto 主机同时损坏时，只能临时用 VPS 上的 OpenList 读取云端仓库，前提是开放其 S3 端口 5246（当前只发布 5244）

## 查看快照

本地仓库：

```bash
task kopiur:snapshots           # 全量
task kopiur:snapshots APP=plex  # 按应用过滤
```

或访问 Kopia WebUI：`https://kopia.<DOMAIN>`，它同样只连接本地仓库

云端仓库：

```bash
kubectl get snapshots.kopiur.home-operations.com -A \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,POLICY:.spec.policyRef.name,PHASE:.status.phase' \
  | grep -- '-cloud '
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
