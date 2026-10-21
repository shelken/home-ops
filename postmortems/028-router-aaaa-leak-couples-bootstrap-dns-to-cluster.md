# Router dnsmasq AAAA 泄漏使自举 DNS 耦合回集群

**日期**: 2026-10-22
**影响**: k8s-gateway 滚动重启窗口内，自举名（ghcr-mirror 等）的 AAAA 查询超时，kopiur 0.10.16 升级连锁锁死；排查先后误判为「yuuko 节点 DNS 配置异常」「公网 DNS 无记录」「daed 链路抖动是唯一根因」「FlClash 出口是根因」，多轮返工
**发现人**: 用户质疑「自举名怎么可能解析失败」触发深挖

## 问题

`router/dnsmasq/dnsmasq-int.hosts` 的设计意图是自举名（ghcr-mirror/minio/pve-mine 等 8 条）在集群不存在时也可解析，但实现用 `addn-hosts`，它只登记 A 记录：自举名的 AAAA 查询在 dnsmasq 本地无记录，落进 `server=/int.ooooo.space/192.168.69.41` 转发给 k8s-gateway。自举解析被静默耦合回集群可用性，文件头的保证从未成立。

## 现象

最小复现（修复前）：

```bash
# 路由器上：A 正常本地应答，AAAA 穿透转发
nslookup ghcr-mirror.int.ooooo.space 127.0.0.1          # → 192.168.6.144
nslookup -querytype=AAAA ghcr-mirror.int.ooooo.space 127.0.0.1  # → 转发 41
```

k8s-gateway 日志持续出现 `192.168.6.1:随机端口` 源的 `AAAA IN ghcr-mirror/minio` NXDOMAIN 应答。

## 当晚时间线（2026-10-21）

| 时间 | 事件 |
|---|---|
| 23:24 | PR #1605 合并（k8s-gateway 3.7.2→4.0.1） |
| 23:27 | k8s-gateway 新 Pod 创建，镜像经同一条慢链路拉取，23:45 才 Ready |
| 23:28 | PR #1533 合并（kopiur 0.10.16），三节点拉新镜像 |
| 23:37:58 | yuuko journalctl：`lookup ghcr-mirror.int.ooooo.space: Try again`（EAI_AGAIN） |
| 23:37:59–23:42:26 | k3s ImagePullBackOff 退避约 4.5 分钟，期间不做任何拉取 |
| 23:42 | Helm 5 分钟 `--wait` 死线到，kopiur/k8s-gateway 双双 UpgradeFailed |

## 关键错误假设（排查走了弯路的原因）

1. **「公网 DNS 有 ghcr-mirror 记录」**——从节点测 1.1.1.1 能解析，实际是 daed 截获后回弹主路由应答；从主路由本机测公网 DNS 才是真值（NXDOMAIN）。测 DNS 必须选无拦截的 vantage point
2. **「宿主机走 daed」**——daed 白名单（wing.db）实际只含 3 个 k8s 节点 + quest/pve；宿主机 `must_direct`，其境外出口是 FlClash TUN，与 daed 无关。误判导致把 mirror 回源慢算到 daed 头上
3. **「mirror 不缓存 blob」**——统计脚本查错目录（`repositories/` 而非 `blobs/`）；实际 mirror-ghcr 缓存 794MB/2068 blob。kopiur 0.10.16 当晚是首拉（缓存必然冷），不构成独立故障
4. **「k8s-gateway 滚动重启是 AAAA 超时的原因」**——Go resolver（containerd）A 成功 + AAAA NXDOMAIN 会正常返回（`dnsclient_unix.go`：有地址即成功，`lastErr` 仅在零地址时返回，`StrictErrors` 默认 false）；NXDOMAIN 不产生 EAI_AGAIN。AAAA 泄漏是真实缺陷（musl 致命，见下），但不是当晚 containerd 报错的充分原因——当晚 A 与 AAAA 必然同时超时，共同瓶颈是 daed 引擎本身
5. **「address= 就能闭合 AAAA」**——实测 dnsmasq 2.91 中 `address=/name/ipv4` 只约束 A 查询，AAAA 仍按 server= 转发，需要补 `local=/name/` 才全类型闭合

## 解析器行为差异（源码级）

musl（Alpine 镜像）`lookup_name.c:173`：A/AAAA 批量发送后顺序检查，**任一应答超时返回 EAI_AGAIN、任一 NXDOMAIN 返回 0→EAI_NONAME，A 已拿到的答案被整体丢弃**——无按族容错。Go 默认恰好相反。同一缺陷对两类运行时是两种故障：musl 常态失败，Go 只在超时（而非 NXDOMAIN）时失败。

## 修复

`router/dnsmasq/conf.d/30-bootstrap.conf.tpl`（替代 int.hosts + 20-hosts.conf）：

```conf
local=/ghcr-mirror.int.ooooo.space/
address=/ghcr-mirror.int.ooooo.space/192.168.6.144
# 8 个自举名各一对；local= 使全记录类型本地闭合（AAAA=NODATA，不转发）
```

- PR #1638（已合并）；部署后 20 秒窗口 k8s-gateway 泄漏查询 0 条；节点 A/集群名解析不受影响
- 代价：addn-hosts 隐含的 PTR 反解丢失（当前无消费方，需要时补 `ptr-record=`）
- declare.py 同步移除 hosts 专属管道，统一纯 conf 渲染

## 连锁放大与已有缓解

DNS 抖动 5 秒被放大成升级锁死，靠两道机制兜底：k3s 退避放大由 HelmRelease `upgrade.remediation.retries: 3` 兜住（18 个缺失的 HelmRelease 已补齐，PR #1637）；k8s-gateway 自身升级与业务升级同时触发的竞争，由本次修复消除自举依赖后失去放大入口。daed 引擎抖动本身当晚无日志可查（wing.db 非声明式、FlClash 无持久化日志），仍不可追溯，属遗留观测盲区。

## 检查方式

```bash
# 路由器：AAAA 必须本地 NODATA（无转发）
ssh <ROUTER> 'nslookup -querytype=AAAA ghcr-mirror.int.ooooo.space 127.0.0.1'
# k8s-gateway：不应再出现自举名的 AAAA 查询
kubectl logs -n network deploy/k8s-gateway | grep -E 'AAAA IN (ghcr|minio)'
# 新增自举站点：Caddyfile 加站点后，在 30-bootstrap.conf 补 local= + address= 一对
```
