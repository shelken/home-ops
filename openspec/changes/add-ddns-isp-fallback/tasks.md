# Tasks: DDNS ISP 智能回退

## 1. 实现
- [x] 1.1 在 `helmrelease.yaml` 中添加 `ip-selector` sidecar 容器
- [x] 1.2 修改 `ddns` 容器的 `IP6_PROVIDER` 环境变量指向本地 sidecar
- [x] 1.3 添加 `MAIN_VPS_IP_V6` 环境变量到 `ip-selector` 容器（使用全局变量替换）

## 2. 验证
- [ ] 2.1 部署后检查 ip-selector 容器日志确认 IP 选择逻辑正常
- [ ] 2.2 检查 ddns 容器日志确认 DNS 更新使用正确的 IP
- [ ] 2.3 验证 Cloudflare DNS 记录值符合预期
