# Kopiur 备份

集群卷备份使用 [Kopiur](https://github.com/home-operations/kopiur) + Kopia，备份至集群外 MinIO (`s3://kopiur`)。

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
      # 若应用以非 1000 用户运行：
      # KOPIUR_PUID: "0"
      # KOPIUR_PGID: "0"
```

组件自动创建：PVC（`IfNotPresent` 保护已有卷）、SnapshotPolicy、SnapshotSchedule（`H * * * *` 自动错峰）、Restore CR。

## 恢复

```bash
task kopiur:restore APP=<app> CONFIRM=<app> NAMESPACE=<ns>
```

详见 `kopiur-restore` skill。

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
