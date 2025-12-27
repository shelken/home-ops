# Change: 新增本地备份服务

## Why

当前备份策略仅将 Docker 数据和 MinIO 数据备份到云端（通过 OpenList S3），存在以下风险：
- 云端依赖：网络故障或服务变动时无法快速恢复
- 恢复速度：从云端恢复大量数据耗时较长
- 覆盖不全：sakamoto-data 中的 media、Work、折腾等用户数据未纳入备份

## What Changes

- 新增 `kopia-local` Docker 容器服务（复用现有入口脚本）
- 创建本地文件系统 Kopia 仓库（独立于云端仓库）
- 配置白名单备份模式：仅备份指定目录
- 备份源：`media/`、`Work/`、`折腾/`、`synogy-data/`、`k8s/storage/`
- 备份目标：`/Volumes/BackUp3T/kopia-local-repo`
- 调度：每 12 小时
- 排除：`media/Downloads/qbittorrent/`、`media/Software/VM/`、系统文件

## Impact

- Affected specs: 无现有 spec 需修改（新增能力）
- Affected code:
  - `compose/sakamoto/docker-compose.yml` - 新增 kopia-local 服务
  - `compose/sakamoto/.env.tpl` - 新增环境变量
  - `compose/sakamoto/kopia/local/repository.config.tpl` - 新增本地仓库配置
  - `compose/sakamoto/kopia/local/policy.json` - 新增本地备份策略
  - `compose/sakamoto/kopia/README.md` - 更新文档
