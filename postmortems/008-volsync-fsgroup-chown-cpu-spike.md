# VolSync fsGroup chown CPU spike

**日期**: 2026-05-27
**影响**: VolSync 整点同步窗口内，控制平面节点 CPU 与负载明显升高，k3s / apiserver / kubelet 响应变慢，Longhorn attach / mount / detach 同窗拥塞。VolSync 的实际 kopia 复制阶段很短，但同步总时长被 attach、mount、kubelet 递归权限处理和 jitter 放大。
**发现人**: 用户

## 问题

多组 VolSync `ReplicationSource` 同时在整点触发。mover Pod 设置了 `fsGroup`，但未设置 `fsGroupChangePolicy`，Kubernetes 默认按 `Always` 处理：每次挂载支持 `fsGroup` 的卷时，kubelet 都会递归检查并修改卷内目录和文件的 owner / permission。

结果是：

- VolSync mover Pod 自身 CPU 不高，容易误判为“不是 VolSync 造成”。
- 实际 CPU 消耗主要落在宿主机侧 `k3s-server` / kubelet 进程，以及 Longhorn `instance-manager` / `longhorn-manager`。
- `lastSyncDuration` 不能直接解释为 kopia 复制耗时；它包含卷准备、attach、mount、权限处理、jitter 和复制阶段。

## 现象

最小取证命令：

```bash
kubectl get pods -A -o json \
  | jq -r '.items[]
  | select(.metadata.name|test("^volsync-src-"))
  | [.metadata.namespace,.metadata.name,.spec.securityContext] | @tsv'

kubectl get events -A -o json \
  | jq -r '.items[]
  | select((.reason // "") == "VolumePermissionChangeInProgress")
  | select((.involvedObject.name // "") | test("^volsync-src-"))
  | [(.lastTimestamp // .eventTime // .metadata.creationTimestamp),
     .metadata.namespace,
     .involvedObject.name,
     .message] | @tsv' \
  | sort

kubectl explain replicationsource.spec.kopia.moverSecurityContext.fsGroupChangePolicy
kubectl explain replicationdestination.spec.kopia.moverSecurityContext.fsGroupChangePolicy

kubectl -n <OBSERVABILITY_NS> get --raw \
  '/api/v1/namespaces/<OBSERVABILITY_NS>/services/http:<PROMETHEUS_SVC>:9090/proxy/api/v1/query?query=topk(25,max_over_time(sum by (namespace,pod,container)(rate(container_cpu_usage_seconds_total{container!="",image!=""}[1m]))[15m:30s]))&time=<END_UTC>'

ssh <CONTROL_PLANE_NODE> 'sudo pidstat -u -p $(pidof k3s-server),$(pgrep -d, -f "containerd|longhorn-instance-manager|longhorn-manager|tgtd|prompp") 1 60'
```

关键输出：

```text
{"runAsUser":1000,"runAsGroup":1000,"fsGroup":1000,"fsGroupChangePolicy":null}
```

```text
VolumePermissionChangeInProgress  Setting volume ownership ... is taking longer than expected, consider using OnRootMismatch
VolumePermissionChangeInProgress  Setting volume ownership ... processed 65414 files.
VolumePermissionChangeInProgress  Setting volume ownership ... processed 44726 files.
VolumePermissionChangeInProgress  Setting volume ownership ... processed 42957 files.
```

```text
fsGroupChangePolicy ... Valid values are "OnRootMismatch" and "Always". If not specified, "Always" is used.
```

Prometheus 历史窗口显示：

```text
namespace_cpu_max_0000_0015
longhorn-system   3.415 cores
observability     0.666 cores
default           0.560 cores
volsync-system    0.032 cores

volsync-src-* max 0.213 cores
```

节点和宿主机侧显示：

```text
<CONTROL_PLANE_NODE> non-idle max 7.553 cores
<CONTROL_PLANE_NODE> iowait max    1.628 cores

sar 10min window:
%user 41.62  %system 28.75  %iowait 9.15  %idle 20.47

pidstat sample:
k3s-server 155% CPU average, single sample up to 499% CPU
containerd  11% CPU average
prompp      15% CPU average
```

对照 VolSync 事件后，多个任务显示：

```text
Pod scheduled -> attach/mount/VolumePermissionChangeInProgress -> jitter started -> kopia started -> Job completed
```

部分已完成任务的 `kopia started -> Job completed` 只有几十秒，而 `scheduled -> jitter started` 接近五分钟。

## 根因

错误假设：

- 只看 VolSync Pod CPU，就能判断 VolSync 是否是 CPU 尖峰来源。
- `lastSyncDuration` 主要代表 kopia 数据复制耗时。
- 参考仓库没有写 `fsGroupChangePolicy`，说明不写有充分理由。
- init `jitter` 能削掉所有整点开销。

实际约束：

- `fsGroup` 权限处理由 kubelet 执行，CPU 归到宿主机侧 `k3s-server` / kubelet，不归到 `volsync-src-*` Pod。
- VolSync CRD 支持 `fsGroupChangePolicy`，未设置时默认 `Always`。
- `Always` 会在每次卷挂载时递归处理支持 `fsGroup` 的卷，文件数多时会显著拖慢 Pod 启动。
- init `jitter` 只有在 attach、mount 和权限处理完成后才启动；它不能削掉前置的 Longhorn 和 kubelet 权限处理峰值。
- 参考仓库使用 Ceph / OpenEBS / NFS repository 等不同存储路径，不能直接证明 Longhorn 环境下不需要 `OnRootMismatch`。

缺失检查点：

- 没有一开始就把 `VolumePermissionChangeInProgress`、`fsGroupChangePolicy:null`、`kubectl explain` 的默认值放在同一条证据链里。
- 没有一开始分离 Pod CPU、namespace CPU、node CPU 和宿主机进程 CPU。
- 没有一开始把 `scheduled -> jitter -> kopia -> completed` 拆成阶段耗时，导致容易把 pre-copy 和 copy 混在一起。

## 修复

本次计划修复：

- 保留 `fsGroup`，只增加 `fsGroupChangePolicy: OnRootMismatch`。
- 同时覆盖源端和恢复端 mover：

```yaml
moverSecurityContext:
  runAsUser: ${VOLSYNC_PUID:=1000}
  runAsGroup: ${VOLSYNC_PGID:=1000}
  fsGroup: ${VOLSYNC_PGID:=1000}
  fsGroupChangePolicy: OnRootMismatch
```

这样不是禁用权限修正，而是仅在卷根目录权限或 group 不匹配时才递归修正。恢复到新 PVC 或权限不匹配的 PVC 时，仍会触发必要修正。

后续验证：

```bash
kubectl get events -A --sort-by=.lastTimestamp \
  | rg 'volsync-src-|VolumePermissionChangeInProgress|permission denied|Permission denied'

kubectl get jobs -A | rg 'volsync-src-|NAMESPACE'

kubectl -n <NS> logs job/<VOLSYNC_JOB> -c kopia --tail=100
```

恢复演练时，对比关键目录 UID/GID/mode：

```bash
stat -c '%u:%g %a %n' <MOUNT_PATH>/<KEY_PATH>
```

## 预防

- VolSync mover 只要设置 `fsGroup`，默认同时设置 `fsGroupChangePolicy: OnRootMismatch`，除非明确需要每次递归修整整棵目录。
- 排查同步慢时必须拆阶段：`Pod scheduled`、首次 attach、`VolumePermissionChangeInProgress`、`jitter started`、`kopia started`、`Job completed`。
- 排查 CPU 尖峰时不要只看 `kubectl top pods`；同时看 node CPU、namespace CPU、Longhorn Pod CPU 和宿主机 `pidstat`。
- 看到 `VolumePermissionChangeInProgress` 的 `processed N files`，优先判断 kubelet 正在做递归权限处理，而不是 kopia 复制慢。
- 参考公开仓库配置只能当起点，不能当结论；必须对照当前存储后端、卷文件数、CRD 默认值和现场事件。
- 恢复权限安全性要靠一次 restore drill 验证关键目录 UID/GID/mode，不靠每次全盘递归 chown 兜底。

参考：

- Kubernetes `fsGroupChangePolicy`: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#configure-volume-permission-and-ownership-change-policy-for-pods
- VolSync permission model: https://volsync.readthedocs.io/en/latest/usage/permissionmodel.html
- Kopia restore flags: https://kopia.io/docs/reference/command-line/common/snapshot-restore/
