# VPS IP 变更

## 检查清单

- [ ] `MAIN_VPS_IP`（SOPS `cluster-secret.sops.yaml`）
- [ ] `MAIN_VPS_IP_V6`（SOPS `cluster-secret.sops.yaml`，供 Envoy Gateway 地理围栏与 Caddy 使用）
- [ ] `dnscontrol`（更新 DNS 解析记录并推送到上游）
- [ ] Loon / Clash / Quantumult X 客户端订阅链接与代理节点配置
- [ ] 开发者本地 SSH 配置文件（`~/.ssh/config`）
- [ ] Tailscale DERP 节点配置（`compose/vps/docker-compose.yml`）

## 常见问题

- CloudCone 选择自动迁移 IP 时若出现双 IP 并存导致 UDP 异常，临时在 VPS 执行：`ip addr del [old_ip]/[old_mask] dev eth0`
