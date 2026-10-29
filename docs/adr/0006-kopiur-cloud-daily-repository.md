---
date: 2026-10-22
status: accepted
---

# Kopiur 云端副本每天直写独立仓库，宿主机 Kopia 不再封装 kopiur 桶

集群 PVC 的异地副本由 Kopiur 每天一次直接写入集群内 OpenList S3 的 `kopia` 桶 `kopiur/` 前缀，成为独立于宿主机 Kopia 仓库（同桶 `main/` 前缀）的云端仓库；本地仓库（MinIO `kopiur` 桶）保持每小时一次。此前宿主机 Kopia 对 MinIO 目录做外层快照，本地仓库维护合并小 pack 时重写出的新 pack（实测一次约 646 MB）对外层是全新的密文文件，导致周期性 600~700 MB 的重复上传（#1622）

## Considered Options

- 保留宿主机外层快照：上传放大无法消除，外层无法识别内层 pack 的内容
- 用 RepositoryReplication 镜像本地仓库：本地维护重写出的新 pack 同样会被整体镜像上云
- 写入宿主机 Kopia 的 `main/` 仓库：该仓库的维护归宿主机 Kopia，两边会争维护权；`main/` 里的 compose 与 MinIO 数据和集群 PVC 没有可去重的内容
- 新建独立桶：OpenList 的桶与网盘目录的映射存在其数据库里，Git 不可管；复用 `kopia` 桶加前缀无需改 OpenList 配置

## Consequences

- 云端每天只收一份快照，日常上传量为 24 小时净增量；异地副本的恢复点从每小时变为每天，细粒度回滚只依赖本地仓库
- 云端副本可独立于本地仓库恢复，切换步骤见 [Kopiur 备份](../11-kopiur.md)
- 云端仓库必须独立成 `kopiur-repository-cloud` Kustomization：OpenList 依赖本地仓库的 Kustomization，两者合并会在冷启动时互相等待
- OpenList 自身的云端副本只能经 OpenList 读取，集群与宿主机同时损坏时无法用云端副本恢复 OpenList。接受该风险，不额外配置第二个网关

## 修订 2026-10-29：云端副本改由 `SnapshotReplication` 集中复制

上面的「每个应用每天直写独立仓库」在 #1646 落地后暴露成本问题：每个应用各生成一套 `${APP}-cloud` SnapshotPolicy 与 SnapshotSchedule，于是每天都为每个卷多做一次快照 + 克隆 + 一个 mover Pod，集群负载与 mover 数量翻倍，而写的还是本地仓库已有的数据。

改为集群级单个 `SnapshotReplication`（`sakamoto` → `cloud-openlist`，声明在 `k8s/infra/common/kopiur-system/kopiur/repository-cloud/`）：

- `selection.latestOnly: true` 只搬本地仓库每个身份的最新快照，不产生卷快照与克隆；传输量就是净增量
- 应用组件只保留本地每小时策略，`${APP}-cloud` 的 SnapshotPolicy、SnapshotSchedule 已删除，删除它们不会带走已有云端快照（`deletion.onScheduleDelete` 默认 `Retain`，改由 catalog 接管为 `discovered`）
- 云端保留策略从「每应用 keepLatest 2 + keepDaily 7」变为集中 `keepDaily 7 + keepWeekly 4`，且 `pruning` 只作用于本复制创建的副本，不碰目标仓库里其他写入者（含上述 discovered 快照）
- 时区不显式声明：复制调度按 `spec.schedule.timezone` → 源仓库 `scheduleDefaults.timezone`（`sakamoto` 为 `Asia/Shanghai`）→ UTC 解析，仍是本地低峰 04:15

代价：上云从「每个应用各自调度」变成单点调度，复制对象不可用期间所有应用都没有新的云端副本；恢复不再有 `${APP}-cloud` 策略可切，改走目标仓库的身份查询，步骤见 [Kopiur 备份](../11-kopiur.md)
