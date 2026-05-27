# Volsync burst overloads longhorn control plane

**日期**: 2026-05-27
**影响**: 一轮整点 VolSync 源端同步触发后，Longhorn 控制面与 Kubernetes 控制面在数分钟内同时拥塞，控制平面节点上的 `k3s` 因 lease 续约失败主动退出；事故窗口内卷附加、Pod sandbox 创建、监控采集与告警链路都受到影响。
**发现人**: 用户

## 问题

多组 VolSync `ReplicationSource` 都使用 `0 * * * *`，虽然 mover Job 会在启动后做随机 sleep，但整点后仍集中创建大量临时卷、快照与 Job。Longhorn 需要在短时间内处理一批 volume、engine、replica、snapshot、instance-manager 对象更新，最终把单控制平面节点上的 etcd / apiserver / k3s 一起拖慢。

## 现象

最小取证命令：

```bash
kubectl get replicationsources -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,SCHEDULE:.spec.trigger.schedule'
ssh <CONTROL_PLANE_NODE_IP> 'sudo journalctl -u k3s --since "2026-05-27 07:06:20" --until "2026-05-27 07:07:15" --no-pager' | rg 'Failed to renew lease|leaderelection lost|Shutting down'
ssh <CONTROL_PLANE_NODE_IP> 'sudo journalctl -u iscsid --since "2026-05-27 07:00:00" --until "2026-05-27 07:04:00" --no-pager'
```

关键现象：

```txt
Failed to renew lease ... lock="kube-system/k3s" err="context deadline exceeded"
Failed to renew lease ... lock="kube-system/k3s-etcd" err="context deadline exceeded"
leaderelection lost
Shutting down ...
```

```txt
Connection... iqn.2019-10.io.longhorn:<PVC_ID> ... is operational now
```

```txt
RunPodSandbox ... volsync-src-<APP> ... error waiting for pod: Get "https://<KUBERNETES_SERVICE_IP>:443/...": context deadline exceeded
```

补充事实：

- 12 个 `ReplicationSource` 全部仍是 `0 * * * *`
- 现场 23 次 iSCSI login 集中在 `150` 秒内完成
- 所有 login 都指向同一个 Longhorn portal / instance-manager
- `k3s` 退出前最后链路是 `Failed to renew lease` → `leaderelection lost` → `Shutting down`

## 根因

错误假设：

- 以为随机时间策略会把定时任务本身打散，等价于错峰 cron。
- 以为根因在 iSCSI 传输层，或者网络链路先坏，Longhorn 只是被动受害。

实际约束：

- `MutatingAdmissionPolicy` 只给 VolSync mover Job 注入 `jitter` initContainer，不会改 `ReplicationSource.spec.trigger.schedule`。
- 现有 jitter 只有 `0~90s`，对 12 组整点同时触发的源端任务来说过短；结果不是削平，而是把峰值压缩进整点后前 `2.5` 分钟。
- 大多数任务真正的数据复制只需要 `8~18s`，少数较重任务也只在 `210~228s`；长达 `10~24` 分钟的 `lastSyncDuration` 主要耗在卷准备、挂载、临时卷/快照对象协调和控制面排队，不在 kopia 传输本身。
- 事故窗口里 etcd 对 `longhorn.io/*`、`volumeattachments`、`persistentvolumeclaims`、`events`、`leases` 的读写普遍升到数百毫秒到数秒，Longhorn 与 k3s 共享同一控制平面资源，最终击穿 lease 更新时限。

缺失检查点：

- 只看 `ReplicationSource` 的 schedule，不足以判断随机化是否生效；必须继续验证 live Job/Pod 是否真的带了 `jitter` initContainer。
- 只看到 iSCSI reset 不够；必须继续对照 `iscsid`、`k3s`、Longhorn 对象日志，区分“存储传输故障”与“控制面过载导致的大量重新附加”。
- 没有提前把 VolSync 源任务按重量分组错峰，导致所有风险都堆到整点窗口。

## 修复

当时修复：

- 把 `k8s/infra/common/volsync-system/volsync/app/mutatingadmissionpolicy.yaml` 里的 mover jitter 从 `0~90s` 提高到 `0~900s`，先削整点后前几分钟的卷附加峰值。
- 保留现有 Flux / GitOps 路径，通过提交让集群下发新策略，不直接手工改集群对象。

以后正确做法：

- jitter 只作为削峰，不把它当成真正错峰。
- 把 `ReplicationSource` 的 cron 从统一整点改成分散分钟，重任务与轻任务分组排布。
- 对高风险缓存卷单独治理容量与频率，避免它们在每轮同步里重复制造控制面抖动。

## 预防

- 看到多个 VolSync 源任务共享同一 cron 时，不要假设 `jitter` 足够，先算任务数、启动窗口、最长时长和下一轮重叠风险。
- 排查 Longhorn / iSCSI 事故时，按顺序同时取三组证据：
  - `ReplicationSource` 的 schedule 与最近时长
  - `iscsid` / kernel 的 login 与 reset 时间线
  - `k3s` / etcd 对 `longhorn.io/*`、`leases`、`pods` 的超时日志
- 若控制平面节点同时承载 Longhorn portal 与 k3s/etcd，整点批处理默认按高风险看待，先错峰再观察。
- 变更前后都记录 UTC 时间线，至少覆盖“首个卷 login”到“k3s lease 失败”这一段，避免把症状错认成根因。
