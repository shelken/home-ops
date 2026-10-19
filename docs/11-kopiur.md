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

默认使用本地 `sakamoto` 仓库。本地 MinIO 或宿主机不可用时改用云端仓库，顺序如下：

1. 确认云端快照存在，缺快照时先手工触发（见下节）。`task kopiur:snapshots` 走的是本地仓库，看不到云端

   ```bash
   kubectl get snapshots.kopiur.home-operations.com -A \
     -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase' \
     | grep '<app>-cloud'
   ```

2. 解除应用对本地仓库 Kustomization 的依赖，否则本地仓库 Degraded 时 Flux 会停止应用 reconcile：

   ```bash
   kubectl patch ks <app> -n <ns> --type=json \
     -p='[{"op":"test","path":"/spec/dependsOn/0/name","value":"kopiur-repository"},{"op":"remove","path":"/spec/dependsOn/0"}]'
   ```

   稳定后从 Git 恢复该依赖；重建集群的灾备流程同样需要这一步

3. 删除 PVC 与 `Restore`，把 `spec.source.fromPolicy.name` 改为 `${APP}-cloud` 后重建。切源时建议同时把 `policy.onMissingSnapshot` 临时改为 `Fail`，让「云端没有快照」响亮失败而不是产出空卷，恢复成功后改回 `Continue`

恢复行为：组件的 `Restore` 带 `mover.inheritSecurityContextFrom.snapshot`，云端缺快照时停在 `Pending`（`MissingRecordedIdentity` 条件 + Warning 事件），不会静默产出空卷；`resolution` 一经写入不再重解析，重试必须删 PVC 重建

详见 `kopiur-restore` skill

### OpenList 自举

`cloud-openlist` 的 S3 后端就是 OpenList 自己，OpenList 全损时无法用它恢复自身：

1. 先从本地 `sakamoto` 恢复 OpenList，OpenList 的云端副本此时只能写不能读
2. OpenList 起来后再用 `cloud-openlist` 恢复其余应用

本地仓库同样不可用时，需在任意可连 189 云盘的环境手工起一个 OpenList 网关（沿用原 S3 凭据与 `kopia` 桶），并把 `ClusterRepository` 的 endpoint 指向它

### 手工触发云端基线

合并后首次云端快照要等下一个 `H 4 * * *` 槽位，最长约 24 小时。等待期间宿主机对 `kopiur` 桶的嵌套快照已停止，如需立刻建立基线，手写一次性 `Snapshot` CR：

```bash
kubectl create -n <ns> -f - <<'EOF'
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: <app>-cloud-baseline-
spec:
  policyRef:
    name: <app>-cloud
EOF
```

是否信任云端保护链，以全部应用的云端基线快照 `Succeeded` 为准，不以清单合并为准

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
