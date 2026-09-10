---
name: kopiur-restore
description: Kopiur 从 kopia 恢复 PVC。Use when PVC 丢失/faulted、定点恢复、kopiur task、Restore/populator 卡住。
---

# Kopiur restore

用 `components/kopiur/backup`（PVC `dataSourceRef` → Restore CR → volume populator）从集群 kopia 恢复。默认 `task kopiur:*`。

**完成标准**：Restore Ready → 应用 PVC Bound → HR/Pod Ready → 挂载有预期数据。

## Gate：infra → apps

运维/debug/**恢复**一律：

1. 先让 **infra** Ready（含其 wait/health 依赖）
2. 再动 **apps**（apps `dependsOn` infra）

卡住时先修 parent gate，再删应用 ks。禁止长期靠 `kubectl apply` 旁路子 ks 顶替 parent。

恢复前先看：`kubectl get ks infra apps -n flux-system`。

## 恢复机制

Kopiur 使用 Kubernetes volume populator 模式：
- `Restore` CR 定义恢复源（`fromPolicy` 指向 `SnapshotPolicy`，`offset: 0` = 最新）
- PVC 的 `dataSourceRef` 指向 `Restore` CR
- 当 PVC 不存在时，Kopiur 控制器自动创建 populator Pod 从 kopia 拉取快照填充新 PVC
- `onMissingSnapshot: Continue` 允许首次部署时无快照也能创建空 PVC

## Steps

### 1. 确认快照

```bash
task kopiur:snapshots APP=<app>
```

有 `APP@…:/pvc/APP` 再继续；无快照则停（CNPG 等改走 barman）。

### 2. 执行恢复

```bash
task kopiur:restore APP=<app> CONFIRM=<app> NAMESPACE=<ns>
```

自动化流程：删 ks → 清死 Restore/PVC/cache PVC → 等 PVC 消失 → flux reconcile 重建 → 等 Restore Ready + PVC Bound + HR Ready。

### 3. 校验

```bash
task kopiur:status APP=<app> NAMESPACE=<ns>
```

**完成**：文首标准；SnapshotSchedule 正常调度，Snapshot 持续 Succeeded。

## Rules

1. 备份时间看 **SnapshotSchedule** `nextSchedule.at` 和 **Snapshot** 的 `Phase: Succeeded`。
2. 恢复只动 Restore CR / 应用 PVC，不拿 SnapshotSchedule 当恢复开关。
3. 死 Restore / faulted PVC / 孤立 cache PVC 必清，再让 populator 重拉。
4. 查快照用 `kopiur-system/kopia`（`task kopiur:snapshots`）。
5. CNPG ≠ 本 SOP。
6. `security` 命名空间的 crowdsec 使用特权 mover（UID/GID 0），命名空间已标注 `kopiur.home-operations.com/privileged-movers: "true"`。

## Task

| 命令 | 作用 |
|---|---|
| `task kopiur:snapshots [APP=]` | 列快照 |
| `task kopiur:restore APP= CONFIRM= [NAMESPACE=]` | 恢复 |
| `task kopiur:status APP= [NAMESPACE=]` | 状态 |

VPS kopia 拉推：`task kopia:*`。实现：`.taskfile/kopiur.yaml`。

## 指针

- `k8s/components/kopiur/backup/`
- `k8s/infra/common/kopiur-system/kopia/`
- `k8s/infra/common/kopiur-system/kopiur/`
