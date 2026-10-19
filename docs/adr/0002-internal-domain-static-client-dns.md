---
date: 2026-09-27
status: accepted
---

# 内部域分层，SFM 客户端使用静态 DNS 应答

内部入口统一迁入独立内部域 `${INTERNAL_DOMAIN}`（如 `int.<MAIN_DOMAIN>`），公网入口保持原域名。使用 SFM 的客户端由 sing-box 本地应答内部名称，业务连接绕过 sing-box TUN 后交给系统的 LAN 或 Tailscale 路由，避免解析依赖家庭 DNS，也避免绑定外部 Tailscale 的动态 utun 名称。该方案保持远程订阅合并流程、独立 SFM 和独立 Tailscale 客户端，不增加本机更新脚本或第二个 Tailscale 节点身份

解析契约、迁移顺序、验收门槛与隔离验证记录见 [内部域与客户端 DNS 契约](../internal-domain.md)，域名分层边界见 [ADR-0003](./0003-internal-dns-via-gateway.md)

## Consequences

- 拼错或未部署的内部子域也会解析到网关，最终由 TLS 或网关拒绝，DNS 不保证返回 NXDOMAIN
- 客户端维护少量固定入口 IP，失去从家庭 DNS 自动发现入口变化的能力
- 内外入口继续使用同一证书 Secret，内部 wildcard 的加入不构成私钥或权限隔离
- 远程订阅服务拿不到客户端动态接口状态，因此不在订阅内保存 utun 名称，也不引入运行期模板替换
