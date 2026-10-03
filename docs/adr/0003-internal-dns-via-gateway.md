# 内网 DNS 由集群侧 k8s-gateway 单一后端应答

家庭 LAN 与 VPS 的 DNS 分流都把主域与内部域交给集群里的 k8s-gateway，由它按当前集群资源应答：主域下集群内的入口解析到对应 Gateway 的 LoadBalancer 地址，集群内没有的名称再由 gateway 转发公网递归。原 OpenWrt external-dns（webhook 写路由器 UCI）整体移除——它以 `upsert-only` + `registry: noop` 写 UCI，资源下线后记录永不删除（#1477）；gateway 不保存任何记录副本，记录生命周期由集群资源天然决定，从机制上消除了该缺口。路由器侧的分流改为声明式：`/etc/dnsmasq.d` 的内容等于仓库 `router/dnsmasq/conf.d` 的渲染结果，规则不再用 `uci set` / `add_list` 逐条修改。gateway 的公网递归改用 DoT（853），使上游查询不落在路由器针对 53 端口的重定向规则上。域名分层边界见 [ADR-0002](./0002-internal-domain-static-client-dns.md)。决策已确认，部署与端到端验证尚未完成

## Considered Options

- 保留 webhook 并启用 sync：该 provider 没有 TXT ownership 的存放位置（UCI 无法保存 TXT 记录），`sync` 会连同手工条目一起删除，否决
- 路由器 Knot 承载动态记录：能精确删除，但要引入 RFC2136/TSIG/TXT 一整套，且主域还须额外挂 `mod-dnsproxy` 才不被权威 NXDOMAIN 遮蔽，依赖固件包是否编译该模块，否决
- 主域继续写路由器本地表、内部域另用独立权威：保留原有本机应答路径，但引入两套后端与两套凭据，维护面与收益不相称，否决
- dnsmasq `address=` 通配覆盖主域：拼错或未部署的名称也会解析到网关，与精确解析相悖，否决

## Consequences

- 内网解析的答案来自集群，路由器只做转发：集群不可用时主域与内部域都只能靠 dnsmasq 的顺序回落（`strict-order` 之后是公网），故障期间首次查询要等上游超时
- gateway 的 `ttl` 从 1 提到 60，dnsmasq 与客户端据此缓存，避免每次查询都跨网络
- 路由器不再承载任何集群记录；`/etc/dnsmasq.d` 只放分流规则与自举 hosts 的引用，`int.hosts` 移到该目录之外，避免被 dnsmasq 当作配置文件解析
- `confdir` 是唯一的一次性引导（`task router:dns:bootstrap`），此后所有规则都由仓库文件声明，不再出现分散的 UCI 变更
- 控制器的 LuCI 凭据随之移除：它的消费者只有 openwrt-dns 与已停用的 passwall-healer，两者都不再存在
- 集群外自举入口仍由 `router/dnsmasq/dnsmasq-int.hosts` 声明，不依赖集群可用性
