# 内部域分层，SFM 客户端使用静态 DNS 应答

内部入口统一迁入 `int.${MAIN_DOMAIN}`，公网入口保持原域名。使用 SFM 的客户端由 sing-box 本地应答内部名称，业务连接绕过 sing-box TUN 后交给系统的 LAN 或 Tailscale 路由，避免解析依赖家庭 DNS，也避免绑定外部 Tailscale 的动态 utun 名称

此决策保持远程订阅合并流程、独立 SFM 和独立 Tailscale 客户端，不增加本机更新脚本或第二个 Tailscale 节点身份。决策已确认，部署与端到端验证尚未完成

## 解析与访问契约

- 集群外内部入口使用精确记录，指向各自入口 IP；精确记录优先于网关通配记录
- 内部子域的 A 查询默认返回 `<INTERNAL_GATEWAY_IP>`，Envoy 根据原始 SNI 与 Host 分发请求
- 内部域规则优先于通用 DNS 分流及 FakeIP；没有提供的 AAAA、HTTPS 等记录返回 `NOERROR` 空结果，不进入通用解析
- 内部域根名称不作为服务入口，不因子域通配规则隐式开放根入口
- 内部目标地址绕过 sing-box TUN，由发起连接的应用使用系统路由；显式 HTTP/SOCKS 代理的应用需要绕过内部域
- 家中通过 LAN 访问，外出通过 Tailscale subnet route 访问；已有路由通告不等于客户端已实际使用，必须分别验证
- Tailscale 不可用时，静态 DNS 仍返回真实 IP，连接可以失败；静态应答不保证整个应用操作的失败时限
- 客户端关闭 SFM 后，外出环境不保证内部域解析；家庭 LAN 和集群内客户端继续使用各自现有 DNS

## 最小改动边界

- `MAIN_DOMAIN` 不变，新增 `INTERNAL_DOMAIN` 表示选定的内部后缀
- Cloudflare ExternalDNS 配置不变，不新增内部域排除规则，不发布内部服务地址
- OpenWrt ExternalDNS 的 sources、domain filter、registry 和同步策略不变；随入口 hostname 更新记录
- 现有主域 Certificate 增加内部 wildcard，保留现有 Secret 与签发、导出、恢复导入链；同步相关证书名称注解，不新建分发体系
- 内部 HTTPRoute、Gateway 的内部 DNS 目标及其消费者同步迁移；同一应用的公网入口保持原域名
- 集群外内部服务同步迁移其入口、证书覆盖及消费者；不为了统一 IP 将这些服务搬到 Envoy 后面
- 公网服务现有的内网解析覆盖保持不变；不再要求外出客户端将整个主域交给家庭 DNS
- icache 保持默认启用和现有 Nix 超时配置，迁移 URL；历史分钟级等待的根因未确定，不作为增设探活机制的依据

静态入口映射归 `proxy` 的订阅配置管理，入口与服务域名归 `home-ops` 管理，Nix 和客户端固定 URL 归 `nix-config` 管理。路由器现有记录和客户端静态应答必须指向相同入口，入口 IP 变化时两侧都需更新

## 已接受的代价

- 拼错或未部署的内部子域也会解析到网关，最终由 TLS 或网关拒绝，DNS 不保证返回 NXDOMAIN
- 客户端维护少量固定入口 IP，失去从家庭 DNS 自动发现入口变化的能力
- 内外入口继续使用同一证书 Secret，内部 wildcard 的加入不构成私钥或权限隔离
- 远程订阅服务拿不到客户端动态接口状态，因此不在订阅内保存 utun 名称；不引入运行期模板替换

## 迁移顺序

1. 在隔离验证环境确认固定版本 sing-box 的通配 A 应答、精确记录优先级、空 AAAA/HTTPS 应答与合并后规则顺序
2. 验证真实客户端在家庭 LAN、外出 Tailscale 下访问内部网关的实际路径，确认连接不被 SFM 重新代理；不通过修改整个默认出站来掩盖失败
3. 准备内部域变量、证书覆盖、入口 hostname 和客户端订阅；先确保 Flux 父级 infra Ready，再迁移 apps
4. 在同一维护窗口切换内部入口及消费者，包括 OIDC 回调、应用公开 URL、移动客户端、导航监控、备份地址和镜像源；不长期维持双域名
5. 更新客户端实际存在的旧主域分流配置；使内部 DNS 故障不再通过主域分流影响公网服务
6. 核对旧入口和 OpenWrt 残留记录，列明删除范围并确认后清理；`upsert-only` 不会随 Git 回滚或 filter 变化自动删除记录

失败时按同一批次回滚订阅、入口及消费者，不将单独回滚 DNS 视为完整恢复；已经写入 OpenWrt 的记录需要单独核对

## 验收门槛

- 实际订阅合并结果经目标版本检查通过；通过 SFM 的应用解析得到预期 A 或空 AAAA/HTTPS 应答，不依赖家庭 DNS 查询
- 家庭 LAN 和外出 Tailscale 环境均完成真实 HTTPS 请求，证书、SNI、Host 和后端一致；不能只用路由表或 DNS 回答代替连接验证
- 精确记录对应的集群外服务正常；公网域仍按原解析与入口工作
- OIDC 登录、回调及移动客户端正常；备份写入和镜像拉取正常
- Tailscale 不可用时公网解析不受影响，内部连接失败行为与 Nix 耗时被实际观察；不得将单次 DNS 成功写成缓存降级已验证
- 实施记录区分本地配置、已发布订阅和已部署资源；隔离 DNS 验证不等于真实 SFM 客户端访问通过

## 隔离验证记录

2026-09-27，使用现有 Linux 沙箱中的 sing-box 1.14.1 完成最小配置的官方 CLI 合并、配置检查和实际 UDP DNS 应答验证，10 项检查通过

- 通配 A 应答保留查询名称与指定入口 IP，精确记录优先于通配规则
- 内部 AAAA、TXT 查询与内部域根名称返回 `NOERROR` 空应答；HTTPS/SVCB 查询由内核基于 A 应答合成记录（`synthesizeAddressResponse`），无法用规则压成空应答，对客户端无害
- 2026-09-27 补充：1.14.1 本机实测七项通过（精确记录、通配、根名 A/AAAA 空、AAAA 空、外部仍走 FakeIP），并补充了根名空应答规则——通配应答对根名的改写不生效（HasSuffix 前导点不匹配），会漏出字面 `*` 记录
- 未部署的内部子域按约定解析到网关，外部名称仍进入 FakeIP
- 使用交付流程相同的分层文件名，反向提供 `-c` 参数后，内部规则仍排在基础规则之前

验证仅使用沙箱 loopback 和文档示例地址，没有创建 TUN、修改系统 DNS 或访问家庭服务；临时配置及进程在结束时清理。此结果覆盖最小配置的合并与 DNS 行为，不覆盖远程订阅服务的完整装配流程，也不覆盖 SFM 1.14.2 的 macOS 运行路径

## 依据

- [home-ops #1493](https://github.com/shelken/home-ops/issues/1493)：内部与公网域名分层
- [proxy #46](https://github.com/shelken/proxy/issues/46)：整个主域依赖家庭 DNS 的故障范围
- [nix-config #81](https://github.com/shelken/nix-config/issues/81)：内部缓存等待问题，历史根因待定
- [sing-box predefined DNS 应答](https://sing-box.sagernet.org/configuration/dns/rule_action/#predefined)
- [sing-box 通配应答名称改写实现](https://github.com/SagerNet/sing-box/blob/f3b79e01/route/rule/rule_action.go#L632-L657)
- [sing-box 默认接口绑定](https://sing-box.sagernet.org/configuration/route/#auto_detect_interface)
- [Tailscale 与其他 VPN 共存](https://tailscale.com/docs/reference/faq/other-vpns)
- [DNS-01 支持内部服务与 wildcard 证书](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)
