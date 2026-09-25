# Lima guestagent 与 chrony 双写时钟振荡

**日期**: 2026-09-25
**影响**: 两个 Lima 节点（`<LIMA-CP>`、`<LIMA-WORKER>`）`NodeClockNotSynchronising` 持续触发；内核 NTP 同步状态每 10s 被清除一次。顺带定位宿主 Mac 时钟被 TUN 代理带偏 0.2~0.7s。
**发现人**: 用户报告时钟告警，要求"找出根因"。

## 问题

Lima guestagent（2.1.1）每 10s 对比宿主时间，偏差 >100ms 即 `settimeofday()` 硬步进。该调用触发内核 `do_settimeofday64 → TK_CLEAR_NTP → ntp_clear()`：置 `STA_UNSYNC`、maxerror 重置 16s——正好命中 `NodeClockNotSynchronising` 的两个条件。chrony 的测量被步进毒化后频率估计锁死在 ~-38k ppm，墙钟每 10s 快 382ms，agent 再拉回，形成自持振荡。宿主侧真实偏差（Mac 慢 0.2~0.7s）是振荡的初始驱动力。

## 现象

```bash
# 告警条件（node-exporter）
min_over_time(node_timex_sync_status[5m]) == 0 and node_timex_maxerror_seconds >= 16

# 振荡指纹：guestagent 每 10s 一条成功步进，drift 值恒定 ~382ms
journalctl -u lima-guestagent | grep "synchronized with host"
# 内核侧：同一采样窗内 sync 1→0、maxerror 0.083→16
```

## 根因

1. **双时钟写入者**：chrony（频率/步进）与 lima-guestagent（settimeofday）互相破坏；agent 步进污染 chrony 测量，chrony 错误的频率补偿又保证 agent 每 10s 都有 >100ms 偏差可踩。
2. **重新暴露触发器**：两天内 VM 新建/多次重启（Lima worker 接入系列 PR）+ ansible 改 `makestep 1 -1` 后 chronyd 重启，频率状态从头重建并漂移到错误平衡点。
3. **驱动力**：宿主 Mac 的 NTP 同步源被本机 TUN 代理劫持（`route get` → `198.18.0.1/utun5`），macOS timed 长期被带偏——guest 被钉向真值后，与宿主的差值即宿主钟差（178ms/685ms）。

**错误假设记录**：

- 把 382ms 当成"两台宿主都慢 382ms"——实际是 guest 被污染频率（38k ppm）× 10s 周期的振荡平衡值，由 guest 动力学决定、两机相同纯属假象巧合。
- 先推测"底层时钟快 3.8%"——`CLOCK_MONOTONIC_RAW` 实测原始钟率误差 <200ppm，快的是 NTP 补偿后的墙钟。

**有效取证方法**：

- **pairwise 测钟差**：以一台机器为公共参考，`两次本地时间戳夹一次远端时间` 取中位差；参考钟偏差在两两相减时抵消。不依赖任何 NTP 即可排出四台钟的相对序。
- **TEST-NET 劫持判定**：向 `192.0.2.1`（无 NTP 服务的死地址）发 NTP 查询，有应答 = 路径上有透明劫持；同一服务器 IP 两条路径答案差秒级 = 有路径在说谎。
- hostagent 日志（`~/.lima/<vm>/ha.stderr.log`）含失败对时的 drift 值与符号，是宿主侧最直接的证据源。

## 修复

1. `ntp.yaml`：Lima guest 部署 systemd drop-in 剥离 agent 的 `CAP_SYS_TIME`（保留其余功能），handler 一次性清空被污染的 `chrony.drift`（#1484，已合并）。
2. 一次性校正后重启复测：开机 0 次步进、chrony 23.5ppm、sync=1、无 maxerror 尖峰——振荡不再复发（#1483 已关闭）。
3. 宿主侧：`MyDirect.list` 加 `DEST-PORT,123`（proxy#44、subconverter#1 已合并），NTP 按端口直连；设备生效后校时（#1485 跟踪中）。
4. 顺带修复：Lima 每次重启换 SSH host key（cloud-init instance-id 每次变化）→ `setup-cloud-init.yaml` 部署 `ssh_deletekeys: false`（#1486/#1487），并挂入 site。

## 预防

- 凡 VM 内跑 NTP 服务，必须保证**只有一个时钟写入者**；Hypervisor 同步代理（guestagent/qemu-guest-agent）与 chrony/systemd-timesyncd 共存时，剥掉代理的改时钟能力。
- 任何走 TUN/代理的设备，NTP（UDP 123）必须 DIRECT：代理上下行不对称直接制造钟差；`DEST-PORT,123` 进 MyDirect.list 是长期规则。
- 排查钟差先跑 pairwise 差值（不依赖 NTP 的硬证据），再谈源质量；不要用"经过可疑路径的 sntp 结果"当基准。
- 时钟类修复必须做"重启回归"：被污染的 drift/状态会持久化，重启后不复发才算修复。
- `node_timex_maxerror_seconds` 跳 16s = 有进程调用了 settimeofday 的指纹，优先排查虚拟化同步代理。
