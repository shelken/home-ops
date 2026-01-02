## ADDED Requirements

### Requirement: Qui Service Deployment

系统 SHALL 部署 Qui 服务作为 qBittorrent 的现代化 WebUI 管理界面。

#### Scenario: Qui 服务正常运行

- **WHEN** Flux 同步完成
- **THEN** Qui Pod 应处于 Running 状态
- **AND** 健康检查端点 `/health` 返回成功

#### Scenario: 通过网关访问 Qui

- **WHEN** 用户访问 `qui.${MAIN_DOMAIN}`
- **THEN** 能够正常访问 Qui WebUI
- **AND** 可以连接和管理 qBittorrent 实例

### Requirement: Qui Secret Management

系统 SHALL 通过 ExternalSecret 从 Azure KeyVault 获取 Qui 所需的敏感配置。

#### Scenario: Session Secret 正确注入

- **WHEN** ExternalSecret 同步完成
- **THEN** Kubernetes Secret `qui-secret` 应包含 `QUI__SESSION_SECRET` 字段
- **AND** Qui 应用能够正确使用该密钥进行会话管理

### Requirement: Qui Data Persistence

系统 SHALL 使用 volsync 组件为 Qui 配置数据提供备份能力。

#### Scenario: 配置数据持久化

- **WHEN** Qui 服务重启
- **THEN** 之前的配置数据应被保留
- **AND** volsync 应按计划执行备份

### Requirement: Qui Resource Limits

系统 SHALL 为 Qui 配置合理的资源请求和限制。

#### Scenario: 资源配额

- **WHEN** Qui Pod 运行
- **THEN** CPU 请求为 10m
- **AND** 内存限制为 512Mi
