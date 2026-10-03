# 路由器主域与内部域 DNS

ExternalDNS 通过原生 RFC2136 写入路由器 Knot，同时管理主域与内部域：`--rfc2136-zone` 指定两个域，provider 按标签数降序取最长后缀匹配。TSIG、签名 AXFR、TXT ownership 与 sync 的声明见 [HelmRelease](app/helmrelease.yaml)

[ExternalSecret](app/externalsecret.yaml) 从 KeyVault `internal-dns` JSON 读取 `TSIG_SECRET`。路由器使用同一密钥；权限依据 [Knot TSIG 与 ACL](https://www.knot-dns.cz/docs/3.5/html/reference.html) 和 [ExternalDNS RFC2136](https://github.com/kubernetes-sigs/external-dns/blob/v0.21.0/docs/tutorials/rfc2136.md)

主域 zone 挂 Knot 的 `mod-dnsproxy`（`catch-nxdomain: on`），集群内没有的名称转发公网递归，因此主域在内部设备仍解析到内网入口、其余走公网 DNS。HTTPRoute 的 `spec.hostnames` 直接产生记录，注解沿用 external-dns 默认前缀

安装、分流、动态 UCI 比对、确认清理与回退见 [内部 DNS 生命周期](../../../../../../docs/router/dns.md)

LuCI RPC 由 passwall-healer 独立使用，不属于本控制器凭据或依赖
