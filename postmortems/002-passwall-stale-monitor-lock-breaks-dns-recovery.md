# Passwall stale monitor lock breaks dns recovery

**作用**: 记录 `router-mine` 上 `53` DNS 超时的真实根因、恢复步骤和后续排查规则，避免下次只盯 `dnsmasq`/`chinadns-ng` 表象而漏掉 `15353` 与监控锁问题。
**日期**: 2026-04-12
**影响**: `router-mine` 的 `53` 对部分域名解析失败，国内域名可答复，`www.google.com`、`openai.com` 等需要走代理链路的域名返回空答复或超时。
**发现人**: 用户

## 问题

`router-mine` 上的 `53` DNS 再次出现超时。现场看起来像是 `dnsmasq` 或 `chinadns-ng` 异常，但真实故障点在 `chinadns-ng` 依赖的 `127.0.0.1:15353` 上游缺失，同时 `passwall` 的监控脚本被旧锁文件卡死，导致 `sing-box` 掉线后无法自动恢复。

## 现象

最小复现命令：

```bash
ssh root@192.168.6.1 'pgrep -af "dnsmasq|chinadns-ng|sing-box"'
ssh root@192.168.6.1 'netstat -lntup 2>/dev/null | grep -E "127.0.0.1:15353|15355|:53 "'
ssh root@192.168.6.1 'nslookup www.baidu.com 127.0.0.1; echo ===; nslookup www.google.com 127.0.0.1; echo ===; nslookup openai.com 127.0.0.1'
ssh root@192.168.6.1 'sed -n "1,80p" /tmp/dnsmasq.cfg01411c.d/dnsmasq-passwall.conf; echo ===; sed -n "1,80p" /tmp/etc/passwall/acl/default/chinadns_ng.conf'
ssh root@192.168.6.1 'ls -l --full-time /tmp/lock/passwall_monitor.lock'
```

关键现象：

```txt
dnsmasq 监听 53 正常
chinadns-ng 监听 15355 正常
127.0.0.1:15353 没有进程监听

server=127.0.0.1#15355
trust-dns 127.0.0.1#15353

nslookup www.baidu.com 127.0.0.1  -> 正常
nslookup www.google.com 127.0.0.1 -> No answer / timeout
nslookup openai.com 127.0.0.1     -> No answer / timeout

/tmp/lock/passwall_monitor.lock 时间停留在 2026-04-07 20:15:06 +0800
```

## 根因

错误假设：

- 以为 `53` 超时就等于 `dnsmasq` 进程挂了，或者 `chinadns-ng` 本身无法监听。
- 以为 `passwall` 开着监控就一定会把缺失进程自动拉起。

实际约束：

- `dnsmasq` 只是入口，真实链路是 `53 -> 15355(chinadns-ng) -> 15353(sing-box DNS inbound)`。
- `chinadns-ng` 的 `trust-dns` 固定指向 `127.0.0.1:15353`。只要 `sing-box` 不在，这条代理 DNS 链路就会断。
- `passwall` 的监控脚本 `/usr/share/passwall/monitor.sh` 会先检查 `/tmp/lock/passwall_monitor.lock`。只要这个锁文件残留，监控循环就一直跳过进程巡检，不会重启掉线的 `sing-box`。
- 当次现场里，`sing-box` 已掉线，但系统日志没有留下 `oom killer`、`segfault` 或明确的强杀记录；能确认的是“掉线后未被恢复”，不能确认最初退出是自退还是被别的流程停掉。

缺失检查点：

- 只查 `dnsmasq`/`chinadns-ng` 进程不够，必须顺着 `dnsmasq-passwall.conf` 和 `chinadns_ng.conf` 继续核对 `15353`。
- 看到 `passwall` 监控进程还活着不够，必须连同锁文件时间戳一起检查，否则会误判“监控正常”。

## 修复

当时恢复方法：

```bash
ssh root@192.168.6.1 'rm -f /tmp/lock/passwall_monitor.lock && /etc/init.d/passwall restart'
```

恢复后验证：

```bash
ssh root@192.168.6.1 'netstat -lntup 2>/dev/null | grep -E "127.0.0.1:15353|15355|192.168.6.1:53|127.0.0.1:53"'
ssh root@192.168.6.1 'nslookup www.google.com 127.0.0.1'
ssh root@192.168.6.1 'nslookup openai.com 127.0.0.1'
```

正确做法：

- 恢复时优先删掉陈旧的 `passwall` 监控锁，再重启 `passwall`，一次性把 `sing-box`、`chinadns-ng` 和 `dnsmasq` 链路重建完整。
- 验证时必须同时确认三段监听和实际解析结果，不能只看进程表。

## 预防

- 排查 `router-mine` 的 DNS 故障时，固定按这条链路检查：`53 -> 15355 -> 15353`。
- 只要 `53` 能答国内域名、不能答代理域名，立即怀疑 `15353` 的 `sing-box DNS` 已掉线。
- 检查 `passwall` 监控时，必须同时看这两项：
  - `pgrep -af monitor.sh`
  - `ls -l --full-time /tmp/lock/passwall_monitor.lock`
- 如果监控锁时间明显早于当前故障时间，直接按“陈旧锁文件卡死监控”处理。
- 恢复后必须用真实域名验证至少两类结果：
  - 直连域名，例如 `www.baidu.com`
  - 代理域名，例如 `www.google.com`、`openai.com`
