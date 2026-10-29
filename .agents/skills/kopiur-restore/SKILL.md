---
name: kopiur-restore
description: PVC 丢失/数据损坏、定点恢复、切到云端仓库恢复，或 Restore/populator 卡住时使用。
---

# Kopiur restore

恢复由备份组件 `k8s/components/kopiur/backup` 声明完成：PVC `dataSourceRef` → 同名 `Restore` → volume populator 自动填充。**不需要恢复脚本**，目标是让 Flux 重建 PVC。

模型、云端切换步骤、演练结论见 `docs/11-kopiur.md`，不在此重复。

**完成标准**：`Restore` Ready → PVC Bound → HR/Pod Ready → 挂载有预期数据。

## Gate：infra → apps

先让 `flux-system/infra` Ready（含其 wait/health 依赖），再处理 `apps`；卡住时先修 parent gate。禁止用 `kubectl apply` 旁路子 Kustomization 顶替 parent。

```bash
kubectl get ks infra apps -n flux-system
```

## 触发恢复

| 场景 | 操作 |
|---|---|
| PVC 已丢失 | 无需操作，Flux 下一次 reconcile 重建 PVC 即触发恢复 |
| PVC 在但数据损坏 | 确认后删除应用的 Kustomization，由父级 `apps` 重建（PVC、`Restore` 随 prune 一并重建） |
| 新集群 bootstrap | 无需操作 |
| 本地仓库不可用 | 按 `docs/11-kopiur.md`「本地仓库不可用时切到云端」提交 Git |

删除 Kustomization 前必须先得到用户确认，并记录为手动集群操作。

## 步骤

1. 确认有快照：本地仓库策略 `${APP}`（云端副本由集群级 `SnapshotReplication` `sakamoto-to-cloud` 推到云端仓库，已没有各应用的 `${APP}-cloud` 策略）

   ```bash
   kubectl get snapshots.kopiur.home-operations.com -n <ns> \
     -o custom-columns='NAME:.metadata.name,POLICY:.spec.policyRef.name,PHASE:.status.phase'
   ```

   `task kopiur:snapshots APP=<app>` 只查本地仓库，本地仓库不可用时会失败

2. 触发恢复（见上表）
3. 校验：`task kopiur:status APP=<app> NAMESPACE=<ns>`，并检查应用数据

## 卡住时

- `Restore` 停在 `MissingRecordedIdentity`：从云端恢复时 catalog 约 5 分钟后才接管云端快照，等待即可，期间不会产出空卷
- 删除 Kustomization 不删备份：快照默认 `onScheduleDelete: Retain`，数据留在仓库并被接管为 `adopted`
- 死 `Restore`、faulted PVC、孤立 cache PVC（`kopiur-cache-<app>`）要先清掉，再让 populator 重拉
- `onMissingSnapshot: Continue`：没有快照时会建出空 PVC，首次部署正常；恢复后若数据为空，先回到步骤 1
- CNPG 不走本 SOP，使用 barman
- `security` 命名空间的 crowdsec 使用特权 mover（UID/GID 0），命名空间已标注 `kopiur.home-operations.com/privileged-movers: "true"`

## 指针

- `k8s/components/kopiur/backup/`
- `k8s/infra/common/kopiur-system/`
- 迁移类操作（少见）：`task kopia:*`，见 `docs/11-kopiur.md`
