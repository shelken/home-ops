# Volsync stale snapshot blocks init

**日期**: 2026-04-03
**影响**: `default` 命名空间里的 `volsync-src-cli-proxy-api` 长时间卡在 init，`cli-proxy-api` 的卷同步停滞。
**发现人**: 用户

## 问题

`cli-proxy-api` 的 VolSync 定时同步卡住。现场看起来像是同步 Pod 一直起不来，但实际问题不在容器本身，而在 VolSync 复用了已经失效的旧临时快照链。

## 现象

最小复现命令：

```bash
KUBECONFIG=./kubeconfig kubectl describe pod -n default volsync-src-cli-proxy-api-c7rmh
KUBECONFIG=./kubeconfig kubectl -n longhorn-system logs daemonset/longhorn-manager --since=6h | rg 'pvc-a98f4594-1a31-4751-8c99-1ccf2a0f16ed|snapshot-77dbec3d-986a-4800-9fb2-dc29f1399b18'
```

关键报错：

```txt
AttachVolume.Attach failed for volume "pvc-a98f4594-1a31-4751-8c99-1ccf2a0f16ed" : rpc error: code = Aborted desc = volume ... is not ready for workloads
failed to create volume ... failed to verify data source: snapshot.longhorn.io "snapshot-77dbec3d-986a-4800-9fb2-dc29f1399b18" not found
cannot find snapshot snapshot-77dbec3d-986a-4800-9fb2-dc29f1399b18 in the source replica
```

## 根因

错误假设：

- 以为是同步 Pod 卡在 init 容器，或者 Longhorn 临时抖动导致卷暂时没挂上。

实际约束：

- `volsync-cli-proxy-api-src` 这个临时卷不是新的，而是一直沿用 `2026-03-30` 那次同步留下的旧引用。
- Kubernetes 里的 `VolumeSnapshot/volsync-cli-proxy-api-src` 还显示可用，但 Longhorn 底层对应的快照 `snapshot-77dbec3d-986a-4800-9fb2-dc29f1399b18` 已经不存在。
- VolSync 后续每次重试都继续引用这张失效快照，于是 Longhorn 永远无法从它创建新的临时卷，Pod 也就一直卡在 init 前。

缺失检查点：

- 只看了 Pod 事件里的“卷没准备好”，还不够；必须继续对到 Longhorn 管理器日志，确认底层快照是否真实存在。
- 只删 Job/PVC 不够干净，旧 `ReplicationSource` 会立刻把同一张坏快照再拉起来。

## 修复

当时恢复方法：

```bash
KUBECONFIG=./kubeconfig kubectl delete replicationsource.volsync.backube -n default cli-proxy-api
direnv exec . flux reconcile kustomization cli-proxy-api -n default --with-source
```

正确做法：

- 直接删除故障的 `ReplicationSource`，让它名下的旧 Job、旧临时卷、旧快照链一起退出。
- 通过 Flux 重新下发，生成一套新的 `VolumeSnapshot`、临时 PVC 和 Job。
- 验证新快照和新临时卷都换了新 ID，且最终 Job `Completed`。

## 预防

- 看到 `ReplicationSource` 长时间停在 `SyncInProgress`，并且 `lastSyncStartTime` 长时间不变时，不要继续等，立刻查 Longhorn 日志。
- 事件里同时出现下面三类报错时，直接按“失效快照链”处理，不要把时间花在 Pod 或镜像上：
  - `volume ... is not ready for workloads`
  - `snapshot ... not found`
  - `SnapshotDeletePending`
- 遇到这类问题，优先删 `ReplicationSource` 再由 Flux 重建；不要只删 Pod、Job 或临时 PVC。
