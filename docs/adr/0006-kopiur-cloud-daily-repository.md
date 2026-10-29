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
