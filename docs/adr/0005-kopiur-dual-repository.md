---
date: 2026-10-20
status: accepted
---

# Kopiur 双仓库：本地每小时与云端每日独立直写

集群 PVC 备份由 Kopiur 原生支持双仓库输出：本地每小时写入 MinIO 供细粒度回滚，云端每天一次直连集群内 OpenList S3 专属前缀 `kopiur/`。宿主机外层 Kopia 排除 `kopiur` 桶，切断内层小时级碎片包在合并重写后被宿主机重复全量快照上云的放大链路

首次建立云端仓库时各应用共用同一仓库跨源去重，实测 12 个活跃应用最新快照逻辑总量约 1.37 GiB，压缩后物理占用约 1~1.5 GB。策略与调度定义见 `k8s/components/kopiur/backup/snapshotpolicy-cloud.yaml` 与 `k8s/components/kopiur/backup/snapshotschedule-cloud.yaml`，运维与恢复流程见 [Kopiur 备份](../11-kopiur.md)

## Considered Options

- 宿主机对 MinIO 目录打外层快照（原架构）：内层 Kopia 维护合并小包产生新 pack，外层无法识别内容而全量重传，导致周期性 600~700 MB 流量突发
- 使用 RepositoryReplication 单库镜像：云端直接同步本地所有 blob，本地维护重打包产生的新 pack 仍会全量镜像上云，无法解决重写流量问题
- 写入现有云端 `kopia/main/` 仓库：宿主机现有备份为加密密文，与业务明文切片去重率为零，还会卷入宿主机每 2~3 天一次的维护重写并引发维护锁冲突

## Consequences

- 云端每天只接收一份快照，不积累小时级碎片包，日常上云量稳定为 24 小时净增量
- 云端仓库独立自治，灾难发生时可直接从 OpenList 恢复 PVC，无需依赖宿主机 MinIO 还原
- 为解开冷启动闭环（OpenList 依赖本地仓库，而云端仓库需要 OpenList 提供端口），云端仓库拆为独立的 `kopiur-repository-cloud` Flux Kustomization，配置 `wait: false`
- 应用恢复默认仍指向本地策略，从云端恢复需将 `Restore.spec.source.fromPolicy.name` 改为 `${APP}-cloud`
- 宿主机 `kopiur` 桶的历史快照按保留期在云端自然过期，不做手工破坏性删除
