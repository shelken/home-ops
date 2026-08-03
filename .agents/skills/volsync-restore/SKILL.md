---
name: volsync-restore
description: VolSync 从 kopia 恢复 PVC。Use when PVC 丢失/faulted、定点恢复、volsync task、RD/populator 卡住。
---

# VolSync restore

用 `components/volsync`（PVC `dataSourceRef` → RD）从集群 kopia 恢复。默认 `task volsync:*`。

**完成标准**：RD mover Successful → 应用 PVC Bound → HR/Pod Ready → 挂载有预期数据。

## Gate：infra → apps

运维/debug/**恢复**一律：

1. 先让 **infra** Ready（含其 wait/health 依赖）
2. 再动 **apps**（apps `dependsOn` infra）

卡住时先修 parent gate，再删应用 ks。禁止长期靠 `kubectl apply` 旁路子 ks 顶替 parent。

VolSync 恢复前先看：`kubectl get ks infra apps -n flux-system`。

## Steps

### 1. 确认快照

```bash
task volsync:snapshots APP=<app>
```

有 `APP@…` 再继续；无快照则停（CNPG 等改走 barman）。

### 2. 删 ks + 清死残留

```bash
task volsync:restore APP=<app> CONFIRM=<app> NAMESPACE=<ns>
```

**完成**：应用 PVC、旧 RD、指向已删卷的 VolumeSnapshot 均不在。只删 ks、留**死快照** → PVC 永久 Pending。

### 3. 重建 ks

infra/apps 均 Ready 后，只由 `flux-system/apps` 从 Git 重建子 ks。Parent 未 Ready 则停止恢复，先修 gate；禁止 `kubectl apply` 旁路。

### 4. 可选定点

```bash
task volsync:restore APP=<app> CONFIRM=<app> NAMESPACE=<ns> TIME=<RFC3339>
```

不传 `TIME` → `manual: restore-once`（最新）。定点须 **新** `trigger.manual` + `restoreAsOf`。

### 5. 校验

```bash
task volsync:status APP=<app> NAMESPACE=<ns>
```

**完成**：文首标准；RS 仅 `schedule`、无永久意外 `manual`。

## Rules

1. 备份时间看 **Source** `lastSyncTime`，不看 Destination。
2. 恢复只动 Destination / 应用 PVC，不拿 Source trigger 当恢复开关。
3. 死 RD / 死 VolumeSnapshot 必清，再让 kopia 重拉。
4. 查快照用 `volsync-system/kopia`（`task volsync:snapshots`）。
5. CNPG ≠ 本 SOP。

## Task

| 命令 | 作用 |
|---|---|
| `task volsync:snapshots [APP=]` | 列快照 |
| `task volsync:restore APP= CONFIRM= NS= [TIME=]` | 恢复 |
| `task volsync:status APP= NS=` | 状态 |

VPS kopia 拉推：`task kopia:*`。实现：`.taskfile/volsync.yaml`。

## 指针

- `k8s/components/volsync/`
- `k8s/infra/common/volsync-system/kopia/`
- https://github.com/shelken/home-ops/issues/1339
