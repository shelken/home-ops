# Router dnsmasq AAAA 泄漏使自举 DNS 耦合回集群

**日期**: 2026-10-22
**影响**: k8s-gateway 升级时单副本先被删，新 Pod 拉镜像 18 分钟，集群 DNS 断档 18 分钟；期间自举名的 AAAA 查询失败，节点镜像拉取全部回退源站，kopiur 0.10.16 升级撞上 Helm 5 分钟超时卡在 UpgradeFailed。排查中一度把真正根因当成错误假设排除，多轮返工
**发现人**: 用户质疑「自举名怎么可能解析失败」触发深挖

## 问题

自举名（集群外的镜像代理、minio 等 8 条）的设计意图是集群不存在时也能解析。实现用的是 `addn-hosts`，它只登记 A 记录。自举名的 AAAA 查询在 dnsmasq 本地没有记录，落进 `server=/<INTERNAL_DOMAIN>/<DNS_GATEWAY>` 转发给 k8s-gateway。自举解析被静默耦合回集群可用性，文件头写的保证从未成立。

k3s 主二进制以 `netcgo` 编译并静态链接 musl，containerd 用 musl `getaddrinfo` 解析镜像域名：A/AAAA 任一失败整个名字作废。k8s-gateway 一断档，自举名就解析失败。

## 现象

```txt
# 节点 containerd.log（/var/lib/rancher/k3s/agent/containerd/containerd.log）
trying next host  host=<ghcr 镜像代理>  error="... lookup <ghcr 镜像代理>: Try again"
trying next host  host=<第三方备用镜像>  error="... lookup <第三方备用镜像>: no such host"

# 旁路由 daed.log
DNS ingress fast path failed; sending SERVFAIL response ... question=[{<ghcr 镜像代理>. 28 1}]
```

`Try again` 是 musl `gai_strerror(EAI_AGAIN)` 的原文（glibc 是 `Temporary failure in name resolution`，Go 纯解析器不会输出这句）。`28` 是 AAAA。

## 当晚时间线（2026-10-21，UTC+8）

| 时间 | 事件 |
|---|---|
| 23:24 | PR #1605 合并（k8s-gateway chart 3.7.2→4.0.1） |
| 23:27:10 | 旧 k8s-gateway Pod 收到 SIGTERM，新 Pod 开始从 codeberg 拉镜像。chart 4.0.1 默认 `maxUnavailable`=1，当时没有 `maxUnavailable: 0` 防护 |
| 23:27:33 | 节点镜像代理 `Try again`，备用端点 `no such host`，回退源站 |
| 23:28 | PR #1533 合并（kopiur 0.10.16） |
| 23:37:58 | kopiur 镜像拉取 `Try again`，kubelet 退避 |
| 23:42:26 | kopiur-controller 拉取完成，耗时 5m05s，Helm 5 分钟 `--wait` 超时，UpgradeFailed |
| 23:45:15 | 新 k8s-gateway 镜像拉完（24.6MB，18m03s） |
| 23:46:30 | k8s-gateway Ready，DNS 恢复 |

## 因果链

1. 单副本 k8s-gateway 在 chart 4.0.1 默认滚动策略下先删旧 Pod
2. 新 Pod 镜像来自 codeberg，`registries.yaml` 没有对应镜像，只能直连源站。codeberg 有 AAAA，节点当时有 RA 学来的 IPv6 默认路由，流量绕过旁路由直连出口被限速（约 23–30 KB/s），见 [027](./027-node-ipv6-ra-route-bypasses-daed.md)
3. 18 分钟里 `<DNS_GATEWAY>` 没有后端（kube-state-metrics：Ready Pod 数为 0）
4. 自举名 AAAA 转发到 k8s-gateway → 超时 → 旁路由回 SERVFAIL → musl 整名失败
5. `registries.yaml` 里所有第三方备用镜像端点都已 NXDOMAIN，回退直接落到源站，经代理或 v6 直连都很慢
6. kopiur 拉取退避超过 Helm 5 分钟死线

## 关键错误假设（排查走了弯路的原因）

1. **「公网 DNS 有镜像代理记录」**：从节点测公网 DNS 能解析，实际是旁路由截获后回弹主路由的应答。从主路由本机测公网 DNS 才是真值（NXDOMAIN）。测 DNS 必须选无拦截的位置
2. **「宿主机走 daed」**：daed 白名单只含 k8s 节点等少数设备，宿主机直连，境外出口是本机 TUN 代理
3. **「镜像代理不缓存 blob」**：统计脚本查错目录（`repositories/` 而非 `blobs/`）
4. **「containerd 是 Go 纯解析器，AAAA NXDOMAIN 无害，所以 k8s-gateway 断档不是原因」**：没核实失败进程实际用哪个解析器，就把真正根因排除了。报错文本 `Try again` 本身就指向 musl
5. **「daed DNS 引擎抖动是根因」**：没有任何证据，因果链不需要它就能闭合
6. **「daed 日志里没有 tcp6 连接，所以不是 IPv6」**：绕过旁路由的 v6 流量根本不会出现在 daed 日志里
7. **「address= 就能闭合 AAAA」**：实测 dnsmasq 2.91 中 `address=/name/ipv4` 只约束 A 查询，AAAA 仍按 `server=` 转发，需要补 `local=/name/`

## 修复

- `router/dnsmasq/conf.d/30-bootstrap.conf.tpl` 替代 `addn-hosts`：每个自举名一对 `local=` + `address=`，全记录类型本地闭合（AAAA 回 NODATA，不转发）。PR #1638
- k8s-gateway `maxUnavailable: 0 / maxSurge: 1`，升级时旧 Pod 撑到新 Pod Ready。`c244424c`（PR #1633）
- 18 个 HelmRelease 补 `upgrade.remediation.retries: 3`。PR #1637
- 节点不接受 RA 默认网关，v6 立即失败回退 v4 经旁路由。PR #1634，见 027
- 代价：`addn-hosts` 隐含的 PTR 反解丢失（当前无消费方，需要时补 `ptr-record=`）

## 预防

- 自举名必须在主路由对**所有记录类型**本地闭合；新增集群外站点时，在 `30-bootstrap.conf.tpl` 补 `local=` + `address=` 一对
- 判断解析失败原因前，先确认失败进程用的是哪个解析器：报错文本区分 musl（`Try again` / `Name does not resolve`）、glibc、Go
- k3s containerd 的逐端点失败和回退只记在 `containerd.log`，不进 journal
- 单副本、承担集群 DNS 的组件，升级前确认滚动策略不会先删旧 Pod
- `registries.yaml` 备用镜像端点会失效且无人知道，检测机制见 #1640

## 检查方式

```bash
# 主路由：自举名 AAAA 必须本地 NODATA（无转发）
ssh <ROUTER> 'nslookup -querytype=AAAA <BOOTSTRAP_NAME> 127.0.0.1'
# k8s-gateway：不应再出现自举名的 AAAA 查询
kubectl logs -n network deploy/k8s-gateway | grep 'AAAA IN <BOOTSTRAP_NAME>'
# k8s-gateway 滚动策略
kubectl get deploy -n network k8s-gateway -o jsonpath='{.spec.strategy}'
```

全过程见 #1641。
