## 1. 准备工作

- [x] 1.1 在 CrowdSec LAPI 上为 firewall bouncer 生成 API key
  - 执行: `kubectl exec -n security deployments/crowdsec-lapi -- cscli bouncers add crowdsec-firewall-bouncer-vps`
- [x] 1.2 将 bouncer API key 添加到 Azure Key Vault (`shelken-homelab/compose-vps/CROWDSEC_FIREWALL_BOUNCER_API_KEY`)
  - 使用 `task secret:set-json-key secret=compose-vps key=CROWDSEC_FIREWALL_BOUNCER_API_KEY value=...`

## 2. 配置文件

- [x] 2.1 创建 bouncer 配置文件 `compose/vps/configs/crowdsec/crowdsec-firewall-bouncer.yaml`
- [x] 2.2 在 `.env.tpl` 中添加 `CROWDSEC_FIREWALL_BOUNCER_API_KEY` 变量

## 3. Docker Compose 配置

- [x] 3.1 在 `compose/vps/docker-compose.yml` 中添加 `crowdsec-firewall-bouncer` 服务定义
  - 使用 `network_mode: host`
  - 添加 `NET_ADMIN` 和 `NET_RAW` capabilities
  - 挂载配置文件
  - 镜像版本: `ghcr.io/shgew/cs-firewall-bouncer-docker:v0.0.34`

## 4. 验证

- [x] 4.1 部署服务并检查日志确认连接成功
- [x] 4.2 验证 iptables 规则已正确创建（检查 CROWDSEC_CHAIN）
- [x] 4.3 测试封禁效果（使用 `cscli decisions add` 封禁 AS198953 的 5 个 CIDR 段）
