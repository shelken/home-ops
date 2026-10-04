# K8s 节点指定外部触发 DNS 由旁路由嗅探代理

K8s 节点（`sakamoto-k8s`、`homelab-1`、`yuuko-k8s`）的 systemd-networkd 主网卡显式配置 `DNS=1.1.1.1 8.8.8.8`，并禁用 `[DHCPv4] UseDNS`。目的是让节点的 DNS 流量必须跨三层网关经过旁路由（TVBox daed），触发 eBPF 域名嗅探与打标，解决境外服务（GitHub、容器镜像源等）因未嗅探而直连被 GFW SNI 重置（`EOF` / `SSL_ERROR_SYSCALL`）的问题。

## 背景与踩坑记录

### 1. 二层直连绕过旁路由嗅探
daed 是基于 eBPF 的透明代理，分流规则（如 `domain(geosite:github) -> proxy`）依赖捕获客户端的 DNS 请求建立 `IP <-> Domain` 映射表。
若节点顺从主路由 DHCP 下发的 `192.168.6.1`，由于节点与主路由在同一个二层网段（VLAN 6），DNS 数据包经交换机直接发给主路由，完全不经过默认网关（`192.168.6.3` daed）。

~~daed 无法感知该域名，随后发往目标 IP 的 HTTPS 流量被当作未知公网 IP 直连送往 F50 出口，触发 GFW SNI 阻断~~

后一句的因果已被实测推翻，保留备查。当前 daed 运行配置的第一条路由规则是 `!mac(...) && !sip(...) -> must_direct`，白名单外的主机整机不进入 daed，在 eBPF 层直连出网；白名单内的主机即使未被嗅探到域名，未嗅探的境外 TCP 仍按 `fallback: proxy` 走代理。断流发生在白名单排除这一层，与是否嗅探到域名无关。实测细节见 [23-daed-on-tvbox.md](../23-daed-on-tvbox.md) 的白名单小节。

### 2. 不能在主路由全局 DHCP 增加 Option 6
daed 配置了严格的客户端白名单（`!mac(...) && !sip(...) -> must_direct`）。
若在主路由 DHCP 全局下发 `Option 6 = 8.8.8.8`：
- 非白名单设备（手机、电视、IoT）的 DNS 查询到达旁路由后命中 `must_direct`，被原样透传出公网；
- 明文 UDP `8.8.8.8:53` 经国内蜂窝网络直连出境必定遭受 GFW 投毒污染；
- 且公网 DNS 无法解析 `*.lan` 与 `*.int.<MAIN_DOMAIN>`，导致普通设备的内网与外网大面积瘫痪。

### 3. 不能将节点 DNS 指定为 223.5.5.5
daed 规则中硬编码了 `dip(223.5.5.5) && dport(53) -> must_direct`（防止自身向阿里 DNS 递归时成环）。发往 `223.5.5.5` 的 DNS 查询会被 daed 跳过嗅探直连出网，返回国内解析 IP，同样无法进入代理。

### 4. 选用 1.1.1.1 与 8.8.8.8 作为触发 IP
`1.1.1.1` 与 `8.8.8.8` 是公网非 CN 地址，节点访问必须走默认网关 `192.168.6.3`。
数据包到达 TVBox 后被 daed 的 `dport(53) -> direct` 拦截进 DNS 引擎：
- 境外域名走海外加密 DoH 解析，并将结果载入 eBPF 映射表；
- 内网域名（`*.<MAIN_DOMAIN>`、`*.lan`）按 daed 既有规则自动转发回主路由 `192.168.6.1` 解析；
- 配置多个（`1.1.1.1 8.8.8.8`）提供高可用备用，不混入内网或阿里 DNS，防止切服后失效。

## 决策

1. 在 `ansible/playbooks/tasks/k8s-dns.yaml` 中，主网卡 drop-in 统一写入 `DNS=1.1.1.1 8.8.8.8` 与 `DNSDefaultRoute=true`，设置 `[DHCPv4] UseDNS=false`。
2. 配置完全内聚在 Ansible 对 K8s 节点的管理范围，主路由 DHCP 与局域网普通设备维持现状。

## 后果

- K8s 节点访问 GitHub、Quay、GHCR 等境外服务 100% 命中 daed 代理，彻底杜绝 TLS 握手 RST。
- K8s 节点对集群自举服务（`*.int.<MAIN_DOMAIN>`）和本地局域网（`*.lan`）的解析正常通过 daed 回弹主路由，不影响内网通信。
- 依赖旁路由 TVBox 正常运行；由于各 K8s 节点的默认路由原本就是旁路由，此设计未引入新增单点故障。
