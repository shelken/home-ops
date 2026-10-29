---
date: 2026-10-29
status: accepted
---

# Kopiur 云端副本改由单个 SnapshotReplication 复制

[ADR-0006](0006-kopiur-cloud-daily-repository.md) 选的云端仓库不变，只换写入方。原方案让每个应用各自直写，每个卷每天多做一次卷快照、暂存克隆与一个 mover Pod，写进云端的还是本地仓库已有的数据；现在由 `kopiur-system/sakamoto-to-cloud` 每天复制本地仓库每个身份的最新快照

## Consequences

- 上云从每应用各自调度变成单点调度。复制对象不可用期间没有新的云端副本，本地每小时备份不受影响
- 改造前直写的快照转为 catalog 的 `discovered`，不在新复制 `pruning` 的范围内，需要时手工清理
- 恢复没有 `${APP}-cloud` 策略可切，改走目标仓库的身份查询，见 [Kopiur 备份](../11-kopiur.md)
