---
date: 2026-10-29
status: accepted
---

# Kopiur 云端异地副本改由单个 SnapshotReplication 复制，取代每应用直写

[ADR-0006](0006-kopiur-cloud-daily-repository.md) 决定把异地副本直写进云端仓库，写入方是每个应用的 `${APP}-cloud` 策略。本决策保留那个云端仓库，只换写入方：`kopiur-system/sakamoto-to-cloud` 每天把本地仓库每个身份的最新快照复制过去。旧方案让每个卷每天多做一次卷快照、暂存克隆与一个 mover Pod，写进云端的还是本地仓库已有的数据

## Considered Options

- 保留每应用的直写策略：备份负载与 mover 数量翻倍，换来的只是把同一份数据再写一遍
- 用 RepositoryReplication 镜像本地仓库：本地维护重写出的 pack 会被整体镜像上云，上传量放大
- 每应用降频到每周一次：仍要为每个卷做卷快照与克隆，只是次数变少
- 云端只留每日一份：复制的 `selection.latestOnly` 只搬最新快照，小时级历史由本地仓库承担

## Consequences

- 上云从每应用各自调度变成单点调度。复制对象不可用期间没有新的云端副本，本地每小时备份不受影响
- 保留策略集中为一份 GFS，由复制的 `pruning` 执行，只作用于它自己创建的副本
- 改造前写入的直写快照转为 catalog 的 `discovered`，不在新复制 `pruning` 的范围内，需要时手工清理
- 恢复没有 `${APP}-cloud` 策略可切，改走目标仓库的身份查询，见 [Kopiur 备份](../11-kopiur.md)
