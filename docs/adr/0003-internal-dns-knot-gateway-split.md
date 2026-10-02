# 内部 DNS 生命周期：路由器 Knot 权威与 k8s-gateway 动态覆盖分工

#1477 的根因是 internal external-dns 以 `upsert-only` + `registry: noop` 写路由器 UCI，资源下线后内网记录永不删除。决策：内部域的精确生命周期交由路由器 Knot 承担（原生 RFC2136、TXT ownership、`policy: sync`），dnsmasq 只负责把内部域转给 Knot；主域的公网同名内网直达保留现有 k8s-gateway 动态覆盖，其 fallthrough 明确指向公网递归并配有序备用。域名分层边界见 [ADR-0002](./0002-internal-domain-static-client-dns.md)。决策已确认，实施尚未开始

## Considered Options

- 维持 webhook 并启用 sync：上游 webhook 无 TXT ownership，sync 会误删路由器手工条目，否决
- dnsmasq `address=` 通配内部域：零新组件，但下线或拼错的名称仍解析到网关，与「精确生命周期」相悖，否决
- Knot 接管整个公网主域：不完整 zone 会以权威 NXDOMAIN 遮蔽公网解析，否决

## Consequences

- 存量迁移必须满足 ownership 条件（带 TXT 重建或删除重建），不能只搬 A/CNAME
- 家庭主路由从 `all-servers` 改为有序查询，防止公网备用与内网答案竞速
- SFM 客户端保持静态内部域应答，精确删除不覆盖 SFM 本地应答
- 第二域名不纳入此分工
