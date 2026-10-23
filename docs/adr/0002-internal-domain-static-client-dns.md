---
date: 2026-09-27
status: accepted
---

# 内部域分层，SFM 客户端使用静态 DNS 应答

内部入口统一迁入独立内部域 `${INTERNAL_DOMAIN}`（如 `int.<MAIN_DOMAIN>`），公网入口保持原域名。使用 SFM 的客户端由 sing-box 本地应答内部名称，业务连接绕过 TUN 交给系统的 LAN 或 Tailscale 路由，不让整个主域的解析依赖家庭 DNS（[proxy #46](https://github.com/shelken/proxy/issues/46)）。该决策保持远程订阅合并流程、独立 SFM 和独立 Tailscale 客户端，不增加本机更新脚本或第二个 Tailscale 节点身份

解析与访问契约见 [ARCHITECTURE](../ARCHITECTURE.md) 的「内部域契约」

## Considered Options

- 把内部域整域委托给路由器 DNS：2026-09-29 在 proxy 试过并撤销。SFM 的 dns 出站无法借道原生 Tailscale utun（proxy #18、#21），外出时内部域查询挂起约 10 秒，关闭 `auto_detect_interface` 后才降到 78 毫秒
- 在客户端保存 utun 名称：远程订阅服务拿不到客户端的动态接口状态，不引入运行期模板替换

## Consequences

- 拼错或未部署的内部子域在 SFM 客户端也会解析到网关，最终由 TLS 或网关拒绝，DNS 不返回 NXDOMAIN
- 客户端维护少量固定入口 IP，入口 IP 变化时路由器记录与客户端静态应答都要更新
- 内外入口继续使用同一证书 Secret，内部通配的加入不构成私钥或权限隔离
- 客户端关闭 SFM 后，外出环境不保证内部域解析；家庭 LAN 和集群内客户端继续使用各自现有 DNS
- Tailscale 不可用时，静态 DNS 仍返回真实 IP，连接会失败
