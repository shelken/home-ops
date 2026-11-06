# Postmortems

只保留根因不显然、会复发、护栏落不进代码的事故。其余教训在对应运维文档或 `.agents/skills/k8s-incident-analysis/REFERENCE.md`，排障时先按症状查文档

| 症状关键词 | 组件 | 报告 |
| --- | --- | --- |
| `NodeClockNotSynchronising`、`node_timex_maxerror_seconds` 跳到 16s、sntp 读数符号反读 | 时钟 / NTP | [023](./023-mac-clock-ntp-direct-diagnosis-pitfalls.md) |
| `downgrading ... is not supported`、`pending-rollback`、`failed calling webhook "validator.longhorn.io"` | Longhorn | [025](./025-longhorn-downgrade-deadlock.md) |
| `unable to load manifest contents`、`BLOB not found`、`MOVE` 返回 201 但正式名不存在、带随机后缀的临时名 | Kopia / openlist WebDAV | [029](./029-kopia-webdav-move-silent-rename-failure.md) |
