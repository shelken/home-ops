# vps-security Specification

## Purpose
TBD - created by archiving change add-crowdsec-firewall-bouncer. Update Purpose after archive.
## Requirements
### Requirement: CrowdSec Firewall Bouncer 防护

VPS 服务器 SHALL 运行 CrowdSec Firewall Bouncer 服务，将 CrowdSec 的封禁决策自动应用到宿主机的防火墙规则中。

#### Scenario: Bouncer 从 LAPI 获取决策并更新防火墙规则

- **WHEN** CrowdSec Agent 检测到恶意 IP 并向 LAPI 报告
- **AND** LAPI 生成封禁决策
- **THEN** Firewall Bouncer 应在 10 秒内获取该决策
- **AND** 将恶意 IP 添加到 iptables/nftables 黑名单中

#### Scenario: Bouncer 服务启动时连接 LAPI

- **WHEN** crowdsec-firewall-bouncer 容器启动
- **THEN** 服务应使用配置的 API key 成功连接到 CrowdSec LAPI
- **AND** 日志中显示连接成功信息

#### Scenario: 防火墙规则持久化

- **WHEN** Bouncer 服务重启
- **THEN** 之前的封禁规则应被重新应用
- **AND** 不会出现规则丢失导致的安全窗口期

### Requirement: Docker 容器网络权限配置

Firewall Bouncer 容器 SHALL 使用 host 网络模式并具有 NET_ADMIN 权限，以便操作宿主机防火墙规则。

#### Scenario: 容器具有操作 iptables 的权限

- **GIVEN** crowdsec-firewall-bouncer 容器使用 `network_mode: host`
- **AND** 容器具有 `NET_ADMIN` 和 `NET_RAW` capabilities
- **WHEN** 容器尝试创建或修改 iptables 规则
- **THEN** 操作应成功执行

