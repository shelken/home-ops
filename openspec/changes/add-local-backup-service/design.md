## Context

sakamoto 是 Mac Mini M4 宿主机，运行 Docker Desktop/OrbStack。现有 Kopia 服务将 Docker 数据和 MinIO 数据备份到云端（OpenList S3）。需要新增本地备份服务，将 sakamoto-data 移动盘的用户数据备份到 BackUp3T 机械盘。

**存储布局**：
- 源：`/Volumes/sakamoto-data` (1.8TB SSD)
- 目标：`/Volumes/BackUp3T` (2.7TB HDD)

## Goals / Non-Goals

**Goals**：
- 快速本地恢复能力
- 覆盖用户数据（media、Work、折腾等）
- 与云端备份独立运行

**Non-Goals**：
- 替代云端备份
- 备份 k8s/lima 虚拟磁盘（由 VolSync 处理）
- 跨机器备份同步

## Decisions

### 1. 独立仓库 vs 共享仓库

**Decision**: 使用独立的本地文件系统仓库

**Alternatives**:
- 共享云端仓库：需要网络，恢复速度慢
- Kopia Server Repository：增加复杂度

**Rationale**: 本地备份的目标是快速恢复，独立仓库更简单可靠。

### 2. 入口脚本复用

**Decision**: 复用现有 `entrypoint.sh`，通过 docker-compose command 传入不同端口

**Alternatives**:
- 新建 `entrypoint-local.sh`：代码重复
- 修改现有脚本添加环境变量：增加复杂度

**Rationale**: 现有脚本已支持 `$@` 传参，无需修改。

### 3. 备份路径模式

**Decision**: 挂载整个 sakamoto-data，在 policy.json 中指定具体备份路径

**Container mounts**:
```yaml
volumes:
  - /Volumes/sakamoto-data:/backup/sakamoto-data:ro  # 整个源盘
  - /Volumes/BackUp3T/kopia-local-repo:/repo         # 仓库目标
```

**Policy paths** (每个路径独立配置 scheduling):
```
shelken@sakamoto-local:/backup/sakamoto-data/media
shelken@sakamoto-local:/backup/sakamoto-data/Work
shelken@sakamoto-local:/backup/sakamoto-data/折腾
shelken@sakamoto-local:/backup/sakamoto-data/synogy-data
shelken@sakamoto-local:/backup/sakamoto-data/k8s/storage
```

**Rationale**: 简化挂载配置，通过 policy 精确控制备份范围和排除规则。

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| 机械盘故障 | 云端备份独立运行作为补充 |
| 磁盘未挂载时容器失败 | 脚本自动处理（connect 失败退出） |
| 两个 Kopia 服务资源竞争 | 备份周期错开（云端 1h/6h，本地 12h） |

## Open Questions

- 无
