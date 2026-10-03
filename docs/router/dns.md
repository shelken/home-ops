# 内部 DNS 生命周期

本页描述仓库声明的下发流程，不代表配置已经在路由器、集群或 VPS 生效

## 职责

- 路由器 dnsmasq 保留 DHCP、LAN 名称与 `router/dnsmasq-int.hosts` 自举记录
- 主域与内部域的动态记录都由路由器 Knot 承载，ExternalDNS 使用签名 RFC2136、TXT ownership 与 sync
- 主域 zone 挂 `mod-dnsproxy` 的 `catch-nxdomain`：集群内维护的名称由 Knot 直接应答，集群内没有的转发公网递归，不用权威 NXDOMAIN 遮蔽公网记录
- dnsmasq 把两个域都转给本机 Knot，家庭 LAN 不经过 k8s-gateway；后者只服务 VPS 与远程链路
- SFM 保留本地静态应答，Knot 删除记录不改变 SFM 的客户端应答

声明见 [`router/knot/knot.conf.tpl`](../../router/knot/knot.conf.tpl)、[路由器 Task](../../.taskfile/router.yaml) 和 [集群控制器](../../k8s/infra/common/network/internal/openwrt-dns/app/helmrelease.yaml)。域名、路由器地址、公网递归地址和 KeyVault 均从既有声明读取

## 准备

安装当前固件源中的 Knot，不新增或混用包源。配置依赖 `zonefile-load: none` 等 zonefileless 语义，以及 `mod-dnsproxy` 的 `catch-nxdomain`，要求 Knot **3.4 或更高且发行包内含 dnsproxy 模块**。`knot:install` 不校验这两点；`knot:sync` 里的 `knotc conf-check` 是唯一关口，若报未知模块或未知配置项，说明该固件的包不满足本方案，需改用其他固件源，或退回「主域保留 dnsmasq 本地表 + 内部域 Knot」

```bash
task router:knot:install
```

KeyVault 的 `internal-dns` JSON secret 需要 `TSIG_SECRET`，内容为 32 字节随机值的 base64。已存在时复用，不覆盖；仅在确认未创建时执行下列命令，替换 `<KEY_VAULT>`

```bash
(
  set -euo pipefail
  umask 077
  keyfile="$(mktemp)"
  trap 'rm -f "$keyfile"' EXIT
  openssl rand -base64 32 | jq -R '{TSIG_SECRET: .}' > "$keyfile"
  az keyvault secret set --vault-name '<KEY_VAULT>' --name internal-dns --file "$keyfile" --output none
)
```

集群 ExternalSecret 和路由器渲染取同一密钥。Knot 只监听 loopback 与路由器私网地址的 5354 端口，UPDATE/AXFR 必须带 TSIG，不新增 WAN 放行。journal 放持久分区并限容量，不直接复制运行中的 LMDB 文件作备份

## 下发顺序

1. 准备新权威，暂不修改生产 DNS 分流
   ```bash
   task router:knot:diff
   task router:knot:sync
   dig @<ROUTER_IP> -p 5354 <MAIN_DOMAIN> SOA
   dig @<ROUTER_IP> -p 5354 <INTERNAL_DOMAIN> SOA
   ```
   `sync` 校验配置后下发，为两个 zone 初始化空 journal 的 SOA/NS 并启用服务。失败恢复旧配置；配置 diff 不显示密钥
2. 通过仓库与 Flux 发布 gateway 和 RFC2136 控制器声明。确认 revision 包含本次变更，先让父级 infra Ready，再处理 apps，不用子 Kustomization 长期绕过父级
   ```bash
   kubectl -n flux-system get kustomizations infra apps
   kubectl -n network get helmreleases k8s-gateway external-dns-openwrt
   kubectl -n network get configmap k8s-gateway -o jsonpath='{.data.Corefile}'
   kubectl -n network logs deployment/external-dns-openwrt
   dig @<ROUTER_IP> -p 5354 <LIVE_INTERNAL_NAME> A
   ```
   必须直查 Knot 确认动态记录已创建。主域与内部域的 HTTPRoute 都从 `spec.hostnames` 与 Gateway status 产生记录，注解沿用 external-dns 默认前缀
3. 展示并确认主路由分流，保留自举 hosts 与其他域规则
   ```bash
   task router:dns:split:diff
   task router:dns:split:sync
   ```
   `sync` 先验证两个 zone 的 SOA 与 gateway 的内部域回主路由规则。dnsmasq 把主域与内部域都交给本机 Knot，不再改动 `all-servers` / `strict-order`，也不再写主域的公网备用规则。已有 `min_ttl` 不自动改变，可能放大缓存有效 TTL，验收时按运行配置核对
4. 更新 VPS 内部域专用规则，配置文件变更必须强制重建或原生重载，普通 Compose up 不保证加载新配置
   ```bash
   task compose:deploy:vps -- --force-recreate dnsmasq
   ```
5. 停止旧 webhook 写入后，比对并清理旧 UCI。下列第二条命令需要替换段名，不会自动选择条目
   ```bash
   task router:dns:cleanup-list
   task router:dns:cleanup -- <UCI_SECTION_1> <UCI_SECTION_2>
   ```
   名单来自当前 HTTPRoute、Ingress、Service 与 UCI `domain`/`cname`，不保存静态清单。集群同名不证明 UCI 归属；手工或孤儿记录逐个核对消费者并输入完整名称确认，最终输入 `DELETE`。第二域名完全排除，自举 hosts 不进入删除范围。配置漂移、旧 writer 未停或已有未提交 UCI 修改时拒绝删除

旧 LuCI 凭据由 passwall-healer 自己持有，保持应用原来的禁用状态，不因 DNS 迁移卸载 LuCI RPC 或删除共享 KeyVault 项

## 验收与资源观察

从路由器、旁路由、VPS 与集群 DNS 分别查询，不能用一条直查结果替代所有链路

```bash
dig @<ROUTER_IP> <LIVE_INTERNAL_NAME> A
dig @<SIDE_ROUTER_IP> <LIVE_INTERNAL_NAME> A
dig @<GATEWAY_IP> <BOOTSTRAP_INTERNAL_NAME> A
dig @<ROUTER_IP> <PUBLIC_NAME_WITHOUT_CLUSTER_RESOURCE> A
dig @<ROUTER_IP> -p 5354 <DELETED_INTERNAL_NAME> A
curl --resolve '<SERVICE_NAME>:443:<EXPECTED_IP>' 'https://<SERVICE_NAME>/'
ssh <ROUTER_TARGET> 'pidof knotd; cat /proc/$(pidof knotd)/status; cat /proc/meminfo; df -k /overlay'
```

- 内部资源创建、更新、删除后 Knot 按 ownership 收敛：内部域删除后直查返回 NXDOMAIN；主域删除后不再返回内网入口地址（有公网同名记录时由 `catch-nxdomain` 转发得到公网答案）。经 dnsmasq 的缓存等待按有效 TTL 判断
- 手工记录不被 sync 修改，无签名 UPDATE/AXFR 被拒绝
- 集群内没有的主域名称经 `catch-nxdomain` 转发公网递归并返回公网答案；内部域不会被转发到公网
- 重启 Knot 后动态 zone 能从 journal 恢复；集群不可用时家庭 LAN 的镜像与备份自举仍可解析
- HTTPS 核对实际证书、SNI、Host 和后端；旁路由既有 NXDOMAIN 差异单独核查，不能宣称换 Knot 会自动修复
- 看 VmRSS 与 MemAvailable，不把 VmSize 的 LMDB 虚拟映射当成常驻内存；小 zone RSS 不代表 journal 写满后的长期峰值

## 回退

下发与清理任务打印备份位置。恢复前先 diff：完整 DHCP 快照会覆盖备份后的其他 DHCP 编辑，只恢复本次确认的变更

回退需同时匹配 GitOps 控制器、Knot 配置、dnsmasq 分流和本次删除的 UCI 条目；只回滚 Git 不会恢复已删除的路由器记录。先恢复权威与相应记录，再恢复分流。保留原有自举 hosts，不批量导入全部历史孤儿记录

Knot 动态数据备份使用官方 `knotc zone-backup`，恢复使用 `zone-restore`；不要复制正在运行的 LMDB 文件

## 官方依据

- [Knot zonefileless、初始化与备份](https://www.knot-dns.cz/docs/3.5/html/operation.html)
- [Knot TSIG、ACL、监听与 journal 配置](https://www.knot-dns.cz/docs/3.5/html/reference.html)
- [ExternalDNS v0.21.0 RFC2136](https://github.com/kubernetes-sigs/external-dns/blob/v0.21.0/docs/tutorials/rfc2136.md)
- [ExternalDNS TXT ownership](https://github.com/kubernetes-sigs/external-dns/blob/v0.21.0/docs/registry/txt.md)
- [dnsmasq 域分流、all-servers 与 strict-order](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)
- [Kubernetes 使用环境变量定义容器参数](https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/#use-environment-variables-to-define-arguments)
