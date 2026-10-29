# Kopiur 备份

集群卷备份使用 [Kopiur](https://github.com/home-operations/kopiur) + Kopia：

- 本地仓库 `sakamoto`：集群外 RustFS 的 `kopiur` 桶，每小时执行一次，用于细粒度状态回滚
- 云端仓库 `yun139`：OpenList 提供的 139 网盘 WebDAV（`/dav/kopiur`），由集群级 SnapshotReplication `sakamoto-to-cloud` 每天同步本地快照；历史 `cloud-openlist`（S3 存储桶）已改为只读归档并停止维护
取舍见 [ADR-0008](adr/0008-kopiur-cloud-snapshotreplication.md)

依赖组件：
- Longhorn（持久卷 CSI 驱动）
- `kopiur-system`（控制器、ClusterRepository 与 Kopia Web 控制台）

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

组件自动生成：PVC（`IfNotPresent` 保护存量数据卷）、本地 SnapshotPolicy 与 SnapshotSchedule（按对象错峰调度）、Restore CR

## 云端副本

集群级单一资源 `k8s/infra/common/kopiur-system/kopiur/replication/snapshotreplication.yaml`（`sakamoto-to-cloud`），源 `sakamoto`，目标 `yun139`。`task kopiur:replicate` 手动触发，绕过每日窗口，成功后顺延下一个自动窗口

## 恢复

恢复过程完全由组件声明驱动：PVC 的 `dataSourceRef` 绑定同名 `Restore`，`Restore` 从 `fromPolicy` 策略拉取最新快照。PVC 缺失时 Flux 自动重建，volume populator 注入数据。删除应用 Kustomization 触发父级重建或全新集群引导均可自动恢复

`task kopiur:snapshots` 与 `task kopiur:status` 仅用于状态审查；数据迁移使用 `task kopia:*`

### 本地仓库不可用时切到云端

没有 `${APP}-cloud` 策略可切。在该应用的 `ks.yaml` 里给 `Restore` 打补丁，数据源指向 `yun139`：`source.identity` 用 `应用名@命名空间:/pvc/应用名`，并显式给 `spec.repository`；`policy.onMissingSnapshot` 改 `Fail`，否则身份没匹配上会建出空卷；选择器只按 `kind: Restore` 写，Flux 先构建后替换 `${APP}`，按 `name` 选不中

同时把 `kopiur-repository` 的 `wait` 改成 `false`，本地仓库恢复后 revert

~~2026-10-22 用 qui 演练从云端恢复成功~~ 切的是已删除的 `${APP}-cloud` 策略，新路径未演练

- 删除 Kustomization 不会清除快照：快照默认策略为 `onScheduleDelete: Retain`，CR 移除后数据依然保留在仓库，后续由 Catalog 接管为 `adopted`
- 恢复过程初期若停留在 `MissingRecordedIdentity` 属正常等待（约 5 分钟），待 Catalog 完成快照接管后即开始拉取数据，不会产生空卷
OpenList 自身的云端副本要经 OpenList 读取。集群与 sakamoto 主机同时损坏时，只能临时用 VPS 上的 OpenList 读取云端仓库，前提是开放其 S3 端口 5246（当前只发布 5244）

## 查看快照

本地仓库：

```bash
task kopiur:snapshots           # 全量
task kopiur:snapshots APP=plex  # 按应用过滤
```

或访问 Kopia WebUI：`https://kopia.<INTERNAL_DOMAIN>`（HTTPRoute 挂在 envoy-internal 上），它同样只连接本地仓库

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
