# Local-Prod

把集群中有状态服务的最新数据迁到 Mac 本地，用 Docker 离线运行同一服务；回网后把本地运行期间的数据变化写回集群。首个适用对象：cli-proxy-api。

## Language

**checkout**:
把数据所有权从集群移到本地：停集群端 workload，把 PVC 数据同步到 Mac，然后本地 Docker 接管服务。
_Avoid_: 迁出、下载

**checkin**:
checkout 的逆操作：停本地 Docker，把本地数据写回 PVC，恢复集群 workload。
_Avoid_: 迁入、回传、上传

**数据所有权 (data owner)**:
任一时刻服务数据只有一个权威写入端，用 REMOTE（集群）或 LOCAL（Mac）标记。不存在双写。
_Avoid_: 主从、同步状态

**REMOTE**:
集群 workload 运行、持有权威数据的所有权状态。本地副本此时只能读作过期快照。

**LOCAL**:
集群 workload 已停、Mac 本地目录持有权威数据的所有权状态。

**data-mover**:
临时创建、用于挂载目标 PVC 以便与 Mac 传输数据的辅助 Pod。迁移完成后即删除。
_Avoid_: 搬运 pod、sync pod

**单写入端 (single-writer)**:
任何时刻最多一个环境对服务数据有写权限，是 checkout/checkin 全流程的前提约束。
_Avoid_: 锁、互斥

**写回前备份 (pre-checkin snapshot)**:
checkin 清空远端数据之前，先把远端现状拉回本地留存的一份拷贝，用于写回失败时后悔。
_Avoid_: 快照（与 CSI VolumeSnapshot 区分）
