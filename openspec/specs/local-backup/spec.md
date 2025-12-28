# local-backup Specification

## Purpose
TBD - created by archiving change add-local-backup-service. Update Purpose after archive.
## Requirements
### Requirement: Local Backup Service

系统 SHALL 提供本地备份服务，将 sakamoto-data 移动盘的用户数据备份到 BackUp3T 机械盘。

#### Scenario: 定时自动备份

- **WHEN** kopia-local 容器运行中
- **AND** 距离上次备份超过 12 小时
- **THEN** 自动创建指定目录的快照

#### Scenario: Web UI 访问

- **WHEN** 用户访问 http://sakamoto.lan:51516
- **THEN** 显示 Kopia Web UI
- **AND** 可浏览和恢复快照

### Requirement: Backup Scope Configuration

系统 SHALL 通过 policy.json 配置备份范围，采用白名单模式。

#### Scenario: 白名单路径备份

- **GIVEN** policy.json 配置了以下路径的 scheduling：
  - `/backup/sakamoto-data/media`
  - `/backup/sakamoto-data/Work`
  - `/backup/sakamoto-data/折腾`
  - `/backup/sakamoto-data/synogy-data`
  - `/backup/sakamoto-data/k8s/storage`
- **WHEN** 定时任务触发
- **THEN** 仅备份上述路径

#### Scenario: 排除规则生效

- **GIVEN** policy.json 配置了排除规则：
  - `media/Downloads/qbittorrent`
  - `media/Software/VM`
  - 系统文件（.DS_Store, .Spotlight-V100 等）
- **WHEN** 创建快照
- **THEN** 排除的目录和文件不包含在快照中

### Requirement: Independent Repository

系统 SHALL 使用独立的本地文件系统仓库，与云端仓库完全分离。

#### Scenario: 仓库独立性

- **GIVEN** kopia-local 使用 `/Volumes/BackUp3T/kopia-local-repo` 作为仓库
- **AND** kopia（云端）使用 OpenList S3 作为仓库
- **WHEN** 其中一个仓库不可用
- **THEN** 另一个仓库不受影响

### Requirement: Failure Notification

系统 SHALL 在备份失败或警告时发送通知。

#### Scenario: Webhook 通知

- **GIVEN** 配置了 KOPIA_WEBHOOK_URL 环境变量
- **WHEN** 备份失败或产生警告
- **THEN** 发送企业微信 Webhook 通知

