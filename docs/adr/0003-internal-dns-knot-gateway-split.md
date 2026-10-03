# 内部 DNS 生命周期：路由器 Knot 统一承载主域与内部域

#1477 的根因是 internal external-dns 以 `upsert-only` + `registry: noop` 写路由器 UCI，资源下线后内网记录永不删除。决策：路由器 Knot 统一承载**主域**与**内部域**两个 zone，ExternalDNS 改为原生 RFC2136 + TXT ownership + `policy: sync`，两类记录都随资源下线精确删除；dnsmasq 把两个域都转给本机 Knot。主域 zone 挂 `mod-dnsproxy` 的 `catch-nxdomain`，把 zone 内未匹配的名称转发公网递归，因此集群内名称在内部设备解析到 192.168.69.45、集群内没有的仍走公网 DNS，不产生权威 NXDOMAIN 遮蔽。Knot 位于路由器本机，它的对外转发是本机 OUTPUT 流量，不经过 NAT PREROUTING，与 `:53` 重定向劫持无关。家庭 LAN 全程不经过 k8s-gateway，后者只服务 VPS 与远程链路。域名分层边界见 [ADR-0002](./0002-internal-domain-static-client-dns.md)。决策已确认

## Considered Options

- 维持 webhook + `upsert-only`：记录永不删除，即 #1477 本身，否决
- 主域保留 dnsmasq 本地表、只让 Knot 管内部域：主域记录仍无精确删除（webhook 侧没有 TXT ownership 的载体），#1477 的主域部分未修，否决
- 主域交 k8s-gateway 动态覆盖：家庭 LAN 的主域查询要跨网络进集群，撤掉原有本地直达；且 gateway 对主域未匹配要递归公网，其上游查询经路由器时会被 `:53` 重定向折返回 dnsmasq，再被送回 gateway 而成环，否决
- Knot 承载主域但不挂 dnsproxy：完整 zone 的权威 NXDOMAIN 会遮蔽公网解析，否决
- dnsmasq `address=` 通配覆盖主域：拼错或未部署的名称也解析到网关，与「精确生命周期」相悖，否决

## Consequences

- 需要 Knot ≥3.4（`mod-dnsproxy` 的 `catch-nxdomain`）；落地前必须在实际固件确认包内含 dnsproxy 模块，否则该方案不成立
- 单个 external-dns 实例即可：provider 改为 rfc2136，`domainFilters` 覆盖主域与内部域，webhook 及其 LuCI RPC 凭据一并退役
- 两个 zone 的记录都具备 TXT ownership 与 `sync` 删除，主域不再依赖 `upsert-only`
- dnsmasq 不再承载主域 UCI 覆盖，旧记录按确认清单清理；`router/dnsmasq-int.hosts` 的集群外自举管道保留
- Knot 的对外转发是本机 OUTPUT 流量，不经 PREROUTING；若劫持规则同时挂在 OUTPUT 链，需另行排除
- 第二域是否并入 Knot 由后续决策，不随本 ADR 自动纳入
- 存量迁移必须满足 ownership 条件（带 TXT 重建或删除重建），不能只搬 A/CNAME
- SFM 客户端保持静态内部域应答，精确删除不覆盖 SFM 本地应答
