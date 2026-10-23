---
date: 2026-09-27
status: accepted
---

# 内部入口迁入独立的内部域

内部入口统一迁入独立内部域 `${INTERNAL_DOMAIN}`（如 `int.<MAIN_DOMAIN>`），公网入口保持原域名，使 DNS zone 分层与 envoy-internal、envoy-external 的网关分层对齐。此前内外记录混在主域一个 zone 里，客户端只能二选一：解析上游指向内网 DNS，则内网 DNS 不可达时公网记录一并失败；指向公网 DNS，则内部记录无法解析（#1493）。内部域不发布到公网 DNS，证书沿用主域 Certificate 并追加内部通配

客户端如何解析内部域由各客户端仓库决定，SFM 客户端的本地静态应答在 proxy 仓库（[proxy #46](https://github.com/shelken/proxy/issues/46)）。解析契约见 [ARCHITECTURE](../ARCHITECTURE.md) 的「内部域契约」

## Consequences

- 内外入口继续使用同一证书 Secret，内部通配的加入不构成私钥或权限隔离
- 入口 IP 变化时，路由器 `int.hosts` 与各客户端的静态应答都要更新
- 内部入口的 hostname、证书覆盖和消费者（OIDC 回调、应用公开 URL、备份地址、镜像源）随域名迁移同步修改，不长期维持双域名
