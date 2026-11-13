# 外部服务以 selector-less Service + EndpointSlice 接入

集群外服务(如 yuuko 上的 oMLX)需要集群内稳定入口与 gateway 后端。决定:每个外部服务注册一个 selector-less Service + 手动 EndpointSlice,后端 IP 存放在 cluster-settings(键如 `YUUKO_IP`,跟随 `ROUTER_IP` 明文先例),由 postBuild substitution 注入;集群内消费与 HTTPRoute 后端一律指向该 Service

## Considered Options

- **ExternalName Service**:被否决。Envoy Gateway 的 HTTPRoute backendRef 不支持 ExternalName 类型(来源: gateway.envoyproxy.io HTTPRoute/traffic-splitting 文档),gateway 域名无法直达;且解析链依赖路由器 DNS,2026-09 实测 homelab-1 上 `yuuko.lan` 曾 NXDOMAIN(现已注册,依赖仍在)
- **EndpointSlice FQDN 地址**:被否决。kube-proxy 不解析 FQDN endpoint,k3s + Cilium 替换 kube-proxy 的场景下同样不可靠
- **应用直接引用 LAN 主机名**(仓库存量做法,如 cli-proxy-api 引用 `sakamoto.lan`):被否决(仅存量保留)。无统一注册点,无法充当 gateway 后端,主机名失效时无兜底
