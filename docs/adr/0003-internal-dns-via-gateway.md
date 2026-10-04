# 集群服务 DNS 由 k8s-gateway 动态应答

家庭 LAN 与 VPS 将主域和内部域中的集群服务名称交给集群内的 k8s-gateway，由它根据当前 HTTPRoute、Service 和 Ingress 应答。集群外自举名称继续由路由器的精确记录应答，不依赖集群可用性。原 OpenWrt external-dns 整体移除，因为它以 `upsert-only` 和 `registry: noop` 写入路由器 UCI，资源下线后无法删除记录（#1477）

路由器 dnsmasq 保持 LuCI 与 UCI 手工管理，home-ops 不接管全局选项、OpenWrt 默认配置目录或手工条目。home-ops 可以独占额外增加的专用配置目录，使其声明与手工管理保持独立。域名分层边界见 [ADR-0002](./0002-internal-domain-static-client-dns.md)

## Considered Options

- 保留 webhook 并启用 `sync`：该 provider 没有 TXT ownership 的存放位置，UCI 无法保存 TXT 记录，`sync` 会连同手工条目一起删除
- 路由器 Knot 承载动态记录：能精确删除，但要引入 RFC2136、TSIG、TXT ownership，且主域还须外挂 `mod-dnsproxy` 才不被权威 NXDOMAIN 遮蔽，依赖固件包是否编译该模块
- 主域继续写路由器本地表、内部域另用独立权威：保留原有本机应答路径，但引入两套后端与两套凭据
- dnsmasq `address=` 通配覆盖主域：未部署或拼错的名称也会解析到网关，不符合精确记录语义
- home-ops 接管 OpenWrt 默认或手工共用的 dnsmasq 配置目录：会覆盖 LuCI、UCI 和手工文件的管理范围

## Consequences

- 集群服务名称的生命周期跟随 Kubernetes 资源，路由器不保存这些名称的副本
- 集群服务解析依赖 k8s-gateway 可用
- 集群外自举名称仍由路由器回答
- 路由器手工配置与 home-ops 专用配置目录具有独立的所有权范围
