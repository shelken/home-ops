# Change: 为 VPS 添加 CrowdSec Firewall Bouncer

## Why

当前 VPS (vps-cc) 已部署了 CrowdSec Agent 用于检测安全威胁，但检测到的威胁并没有在防火墙层面被实际阻断。添加 Firewall Bouncer 可以将 CrowdSec 的决策（IP 封禁）自动应用到宿主机的 iptables/nftables 规则中，实现真正的入侵防护。

## What Changes

- 在 `compose/vps/docker-compose.yml` 中新增 `crowdsec-firewall-bouncer` 服务
- 新增配置文件 `compose/vps/configs/crowdsec/crowdsec-firewall-bouncer.yaml`
- 在 `.env` 中添加 bouncer API key 环境变量

### 技术方案

使用社区维护的 Docker 镜像 `ghcr.io/shgew/cs-firewall-bouncer-docker`，该镜像：
- 基于 Alpine Linux，轻量级
- 支持环境变量替换配置
- 自动跟踪上游更新
- 活跃维护（最近更新于 2025-12）

### 关键配置要求

1. **网络模式**: 必须使用 `network_mode: host` 才能操作宿主机防火墙
2. **权限**: 需要 `NET_ADMIN` 和 `NET_RAW` capabilities
3. **防火墙后端**: 使用 `iptables` 模式（Docker 默认使用 iptables 管理网络）
4. **API 连接**: 连接到现有的 CrowdSec Local API（通过 `CROWDSEC_LOCAL_API_URL` 环境变量）

## Impact

- Affected code: `compose/vps/docker-compose.yml`, `compose/vps/configs/crowdsec/`
- Dependencies: 依赖现有的 `crowdsec-agent` 服务提供的 Local API
- 需要在 CrowdSec 控制台或 LAPI 上为 bouncer 注册一个 API key
