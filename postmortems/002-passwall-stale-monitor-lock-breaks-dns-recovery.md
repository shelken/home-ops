# Passwall incomplete dns recovery misses sing-box

**作用**: 记录路由器代理 DNS 链路失效的真实根因、错误假设和修复规则，避免下次只重启 `chinadns-ng` 却漏掉 `15353` 的 `sing-box DNS`。
**日期**: 2026-05-02
**影响**: 路由器 `53` 对直连域名仍可解析，但代理域名超时，导致集群 CoreDNS/Flux/Gatus 出现间歇 DNS 故障。
**发现人**: 用户

## 问题

路由器代理 DNS 探测持续失败。`passwall-healer` 日志显示 `chinadns-ng` 重启成功，但代理域名仍然通过 `<ROUTER_IP>:53` 查询超时。

这次真实故障点不是 `dnsmasq`，也不是 `chinadns-ng` 本身，而是 `chinadns-ng` 依赖的上游 `127.0.0.1:15353` 缺失。该端口由 Passwall 生成的 `sing-box` DNS 进程提供。旧 healer 只恢复了 `script_func/2` 的 `chinadns-ng`，没有恢复 `script_func/1` 的 `sing-box`，所以会错误报告“重启成功”但业务仍未恢复。

## 原报告错误描述

原报告里这些判断在最新现场不成立：

- **错误**: “`passwall` 的监控脚本被旧锁文件卡死，导致 `sing-box` 掉线后无法自动恢复。”
  **修正**: 最新现场没有发现监控锁残留；监控锁不是本次可证实根因。

- **错误**: “恢复时优先删掉陈旧的 `passwall` 监控锁，再重启 `passwall`。”
  **修正**: 当前不应把删锁作为标准恢复动作。正确恢复点是显式恢复 `script_func/1` 的 `sing-box DNS` 和 `script_func/2` 的 `chinadns-ng`，再验证端口和真实解析。

- **不完整**: “`sing-box` 已掉线，但无法确认最初退出原因。”
  **修正**: 仍无法确认最初退出原因；但最新证据进一步排除了配置错误、端口冲突、二进制损坏、OOM/segfault。更准确表述是：**没有证据显示 `sing-box` 崩溃；能确认的是 15353 进程缺失，且旧 healer 没有恢复它。**

## 现象

最小复现命令：

```bash
dig +time=2 +tries=1 @<ROUTER_IP> <PROXY_DOMAIN> A
dig +time=2 +tries=1 @<ROUTER_IP> <DIRECT_DOMAIN> A

kubectl logs -n observability deploy/gatus --all-containers --since=10m \
  | grep '<ROUTER_DNS_PROXY_ENDPOINT>'

# 通过 LuCI RPC 在路由器上检查
pidof sing-box
pidof chinadns-ng
netstat -lntup 2>/dev/null | grep -E '127\.0\.0\.1:15353|:15355|:53 '
sed -n '1,120p' <PASSWALL_CHINADNS_CONFIG>
sed -n '1,20p' <PASSWALL_SCRIPT_FUNC_1>
sed -n '1,20p' <PASSWALL_SCRIPT_FUNC_2>
```

关键现象：

```txt
@<ROUTER_IP> <PROXY_DOMAIN> A   -> timeout
@<ROUTER_IP> <DIRECT_DOMAIN> A  -> NOERROR

<ROUTER_DNS_PROXY_ENDPOINT> success=false
<ROUTER_DNS_ENDPOINT> success=true

dnsmasq 监听 :53 正常
chinadns-ng 监听 :15355 正常
127.0.0.1:15353 没有监听

<PASSWALL_CHINADNS_CONFIG>:
trust-dns 127.0.0.1#15353
group-upstream 127.0.0.1#15353

<PASSWALL_SCRIPT_FUNC_1>:
<PASSWALL_SING_BOX_COMMAND>

<PASSWALL_SCRIPT_FUNC_2>:
<PASSWALL_CHINADNS_COMMAND>
```

## 根因

错误假设：

- 以为 `chinadns-ng` 重启成功就等于代理 DNS 链路恢复。
- 以为 `15355` 存在就足够，漏查 `chinadns-ng` 的上游 `127.0.0.1:15353`。
- 以为 healer 的成功条件可以只看 `chinadns-ng` PID 变化。
- 以为本次仍是陈旧 `passwall` 监控锁卡住监控；最新现场没有这个证据。

实际约束：

- 真实链路是：`dnsmasq :53 -> chinadns-ng :15355 -> sing-box DNS :15353`。
- `15353` 不由 `chinadns-ng` 管理，而由 `sing-box` 提供。
- `chinadns-ng` 活着但 `15353` 缺失时，直连域名可能仍正常，代理域名会超时。
- `sing-box check` 通过，手动按 `script_func/1` 启动后 `15353` 可稳定监听，说明配置、二进制、端口绑定不是当前失败原因。
- 系统没有 OOM、segfault、kernel kill 证据；`sing-box` 的日志被 Passwall 丢弃，无法还原最初退出原因。

缺失检查点：

- healer 没有检查 `script_func/1`。
- healer 没有检查 `127.0.0.1:15353`。
- healer 没有用真实代理域名做最终验证。

## 修复

已修复 `passwall-healer` 的恢复脚本：

- 显式查找 `script_func` 中的 `sing-box run` 命令；缺失则失败。
- 显式查找 `script_func` 中的 `chinadns-ng` 命令；缺失则失败。
- 按顺序恢复：
  1. 停旧 `sing-box` / `chinadns-ng`
  2. 启动 `sing-box`
  3. 验证 `127.0.0.1:15353` 监听
  4. 启动 `chinadns-ng`
  5. 验证 `:15355` 监听
  6. 验证代理域名解析成功
- 任一检查失败直接返回 500，不做兜底。

验证结果：

```txt
luci exec response={"id":1,"result":"__PASSWALL_DNS_RECOVERED__\u000a","error":null}
passwall dns recovery ok

@<ROUTER_IP> <PROXY_DOMAIN> A -> NOERROR
<ROUTER_DNS_PROXY_ENDPOINT> success=true
```

## 预防

- 排查路由器代理 DNS 故障时，固定按这条链路检查：`53 -> 15355 -> 15353`。
- 直连 DNS 正常但代理 DNS 失败时，优先检查 `127.0.0.1:15353` 的 `sing-box DNS`。
- 不准把 `chinadns-ng` PID 变化当作恢复成功。必须同时验证：
  - `127.0.0.1:15353` 监听
  - `:15355` 监听
  - 代理域名可通过路由器 DNS 解析
- 不准把“监控锁卡住”当默认根因。只有现场存在监控锁且时间明显异常时，才按锁问题处理。
- 如果要追踪 `sing-box` 最初退出原因，必须先让 Passwall 保留 `sing-box` 输出，否则事后没有可用证据。
