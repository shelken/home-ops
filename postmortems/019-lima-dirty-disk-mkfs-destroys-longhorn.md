# lima 脏盘误格式化销毁 Longhorn 数据盘

**日期**: 2026-08-01
**影响**: `<CONTROL_PLANE_NODE>` 的 Longhorn 数据盘 `<LONGHORN_DEVICE>` 被 `mkfs.ext4` 覆盖，Grafana、Mosquitto、Immich DB、Metatube、Alertmanager、Prometheus、Pocket ID 的单副本卷 faulted；Metatube、Pocket ID 由 kopia 恢复，Immich DB 由 CNPG Barman 恢复，其余四个服务空卷重建；另有 11 个 VolSync destination 临时卷失效，后续由源端备份重新回填
**发现人**: Gatus 告警后排查

## 问题

执行集群关停后，VM 因 diffdisk GPT 损坏无法启动。修复 GPT 后，VM 在脏盘状态下反复异常启停，最终 Lima 的 `05-lima-disks.sh` 把仍带旧数据的 Longhorn 盘误判为「未初始化」，执行 `sfdisk` 和 `mkfs.ext4`，覆盖 Longhorn 副本数据

## 现象

```bash
# VM 内 cloud-init 日志
[[ ! -b <LIMA_DISK_LABEL_LINK> ]]                # label 缺失，脚本误判
Created a new GPT disklabel                       # sfdisk 重建分区表
Partition #1 contains a ext4 signature            # 旧 ext4 仍存在
mkfs.ext4 -L lima-longhorn <LONGHORN_DEVICE>      # 覆盖文件系统

# Longhorn 侧
reason: DiskFilesystemChanged
# Node 状态仍记录 <OLD_DISK_UUID>，磁盘配置文件已是 <NEW_DISK_UUID>
```

`dumpe2fs` 显示文件系统创建时间对应事故时刻，累计写入量仅数 MiB，证明原数据已被覆盖

## 根因

三层事故因果链：

1. **cluster-stop 关机顺序错误**：`cluster-stop.yml` 先停止 k3s，Longhorn 引擎随之退出，但卷仍挂载；随后 VM poweroff 时 `<LONGHORN_MOUNT>` 卸载失败，并出现 `device offline`、`lost sync page write`、`JBD2 I/O error`，数据盘先进入脏状态
2. **Lima `05-lima-disks.sh` 判定不可靠**：脚本只检查 `<DISK_LABEL_LINK>`。脏盘启动时 udev 未创建该链接，脚本在 `format` 默认开启的情况下直接执行 `sfdisk` 和 `mkfs.ext4`。上游行为见 [Lima 默认模板](https://github.com/lima-vm/lima/blob/master/templates/default.yaml) 和 [udev 竞态 Issue #4830](https://github.com/lima-vm/lima/issues/4830)
3. **单副本和备份覆盖不足**：七个业务卷都是单副本；Metatube、Pocket ID 和 Immich DB 可从独立备份恢复，Grafana、Mosquitto、Prometheus、Alertmanager 没有有效备份，只能接受历史数据丢失并创建空卷

恢复阶段还有两个实际约束：

- **Longhorn 不会自动接纳文件系统 UUID 已变化的磁盘**：Node spec 和 status 保留旧 UUID，磁盘上的 `longhorn-disk.cfg` 已生成新 UUID，因此磁盘持续为 `DiskFilesystemChanged`、`Ready=False`、`Schedulable=False`，即使文件系统已空且可挂载也不会自动恢复调度
- **唯一可用磁盘的调度额度不足**：`storage-over-provisioning-percentage=100` 时，另一节点虽有足够物理空间，但已调度容量只剩不足 70Gi；因此 1Gi Alertmanager 卷可创建，70Gi Prometheus 卷没有可用副本位置并立即 faulted。Prometheus 的硬节点亲和性不限制 Longhorn 副本跨节点放置，但会阻止 Pod 在目标节点故障时迁移

错误假设：

- 先停止 k3s 再关机是安全流程，实际会先杀死 Longhorn 引擎
- additionalDisks 有旧数据时 Lima 不会格式化，实际只依赖易失的 by-label 链接
- mkfs 后的空盘会被 Longhorn 自动重新纳入，实际必须清除旧磁盘登记并重新添加

## 修复

### 数据和服务恢复

1. 使用 kopia 恢复 Metatube 和 Pocket ID
2. 删除并由 Flux 重建 CNPG Cluster，Immich DB 从 Barman 最新备份和 WAL 恢复
3. Grafana、Mosquitto、Prometheus、Alertmanager 无备份，删除 faulted PVC 后创建空卷
4. 始终先恢复 `flux-system/infra`，确认 Ready 后再恢复 apps

恢复工具和 SOP 见：

- `.agents/skills/volsync-restore/SKILL.md`
- `.taskfile/volsync.yaml`
- `k8s/infra/common/database/cloudnative-pg/README.md`

### Longhorn 磁盘重新纳入

恢复前先确认 `<LONGHORN_MOUNT>` 是预期 ext4 挂载点、容量正确，且不是系统盘目录。磁盘文件中的新 UUID 与 Longhorn Node status 中的旧 UUID 不一致

1. 盘上仍有 11 个 stopped replica CR，全部属于 7 个 `ReplicationDestination` 创建的 restore-once 临时 PVC
2. 验证这些 PVC 无业务 Pod 挂载，源端 `ReplicationSource` 最近同步成功，因此可安全重建
3. 暂停相关子 Kustomization，删除 7 个 `ReplicationDestination`，由 ownerReference 正常级联删除 11 个临时 PVC、PV、Longhorn 卷和 replica CR；未强制移除 finalizer
4. 从 `nodes.longhorn.io/<CONTROL_PLANE_NODE>.spec.disks` 删除旧 disk entry，等待对应 `status.diskStatus` 消失
5. 使用相同 diskName、相同挂载路径和原 `storageReserved` 重新添加 disk entry，同时设置 `allowScheduling: true`
6. 验证磁盘状态读取新 UUID，且 `Ready=True`、`Schedulable=True`、可用容量正常
7. 第一次创建的 Prometheus 空卷已在磁盘恢复前 faulted，因此暂停其 Kustomization，将 Prometheus CR 临时缩容到 0，删除 faulted PVC，再恢复副本数和 Flux；新卷在目标节点 attached/healthy
8. 按 infra → apps 顺序恢复所有暂停的 Kustomization；7 个 `ReplicationDestination` 由 Flux 重建并完成一次回填

最终验收：

- Grafana、Mosquitto、Prometheus、Alertmanager Pod Running
- 对应 PVC Bound，Longhorn 卷 healthy
- 全局 faulted Longhorn 卷数量为 0
- `<CONTROL_PLANE_NODE>` 磁盘 Ready、Schedulable、allowScheduling
- `flux-system/infra` 和 `flux-system/apps` Ready
- 无暂停 Kustomization、临时缩容或强制 finalizer 残留

### 防复发变更

- `ansible/playbooks/cluster-stop.yml`：不再先停止 k3s，改为直接优雅关闭节点；超时后报错，不自动 force stop
- `ansible/playbooks/cluster-start.yml`：启动 Lima VM 前执行 `limactl disk unlock longhorn`
- `ansible/playbooks/install-k3s.yaml`：k3s 启动前确认 Longhorn 路径是真实挂载点
- `docs/resource/lima/`：control-plane VM 的 additionalDisks 显式设置 `format: false`

## 预防

- cluster-stop/start 变更后执行 `ansible-playbook --syntax-check` 和一次真实演练；确认 Longhorn 挂载点干净卸载，日志无 JBD2 I/O error
- 优雅关停失败时禁止自动 force stop，先处理仍挂载的卷和阻塞进程
- Lima additionalDisks 必须显式设置 `format: false`
- k3s 启动前必须通过 Longhorn 数据盘挂载检查
- 单副本 Longhorn 业务卷必须有独立备份；ReplicationSource 超过 7 天未成功应告警
- 处理 `DiskFilesystemChanged` 时，先验证挂载设备、容量、磁盘配置 UUID、业务挂载和剩余副本，再清理 disk entry
- 脏盘不等于空盘；自动化看到已有文件系统签名后不得继续执行 mkfs
