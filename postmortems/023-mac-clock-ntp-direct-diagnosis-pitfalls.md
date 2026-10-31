# 宿主 Mac 与 Lima 节点时钟 NTP 诊断：测量陷阱与双时钟写入者

**日期**: 2026-09-26
**症状关键词**: `NodeClockNotSynchronising`、`node_timex_maxerror_seconds` 跳到 16s、`node_timex_sync_status` 每 10s 归零、`settimeofday` 步进、sntp 读数符号反读、TUN 代理劫持 NTP
**影响**: 节点时钟告警持续触发，宿主侧收尾验收连续多轮误判，实际规则早已生效

## 症状

```bash
# 告警条件（node-exporter）
min_over_time(node_timex_sync_status[5m]) == 0 and node_timex_maxerror_seconds >= 16
# VM 内每 10s 一条成功步进、drift 恒定；内核侧同窗 sync 1→0、maxerror 0.083→16
journalctl -u lima-guestagent | grep "synchronized with host"
# 同一时刻两种测法给出相反结论
sntp -t 3 <NTP_SERVER>   # 数值 IP，结果被误读成假源应答
```

## 根因

- VM 内有两个时钟写入者：chrony 与虚拟化同步代理互相破坏，代理步进污染 chrony 测量，chrony 的错误频率补偿又保证代理每 10s 都有 >100ms 偏差可踩，形成自持振荡
- 代理的 `settimeofday` 触发 `do_settimeofday64 → TK_CLEAR_NTP → ntp_clear()`，置 `STA_UNSYNC` 并把 maxerror 重置 16s，正好命中告警的两个条件；`node_timex_maxerror_seconds` 跳到 16s 是有进程调用 `settimeofday` 的指纹，优先查虚拟化同步代理
- 宿主 Mac 的 NTP 源被 TUN 代理带偏，是振荡的初始驱动力；`timed` 是偶发校正加长时间自由漂移（实测 −20ppm 量级），不做连续锁相，按「稳定 <100ms」验收 stock `timed` 不可达成
- `sntp` 输出的 offset 是「服务器 − 本地」，正值表示本地落后；按「本地 − 服务器」解读，会把直连生效的诚实读数读成劫持

## 排查陷阱

- 数值 IP 探测命不中域名规则，连接页实拍只证明被探测的那条流；要验证「某条分流规则生效」，探测必须与真实流量同构（同域名），否则 fake-ip 走的路径不一致
- GUI 客户端数据库里的字段只是界面状态，不等于运行模式；代理类客户端改订阅后必须重启内核进程，判断依据是 core 进程启动时间，不是配置文件 mtime
- 跨轮比较绝对差值是参照系抖动；发起测量的机器要先自证诚实（`chronyc tracking` RMS <1ms），多机轮测用同一轮内两两夹测
- 多个理论都能拟合数据时不要反复换叙事，去设计能一锤定音的观测

```bash
# pairwise 夹测：以一台机器为公共参考，两次本地时间戳夹一次远端时间取中位差
# 参考钟偏差在两次相减时抵消，不依赖 NTP 就能排出各机的相对序
# 透明劫持判定：往 TEST-NET 死地址（无 NTP 服务）发 NTP 查询，有应答即有透明劫持
sntp -t 3 192.0.2.1
```

## 修复

- 部署 systemd drop-in 剥离虚拟化同步代理的 `CAP_SYS_TIME`（保留端口转发等其余功能），清空被步进污染的 `chrony.drift` 后重启
- 走 TUN/代理的设备，NTP（UDP 123）必须直连（`DEST-PORT,123` 进直连规则），代理上下行不对称会直接制造钟差
- 验收改用双源交叉：pairwise 夹测加宿主侧 hostagent drift，不拿经过可疑路径的 `sntp` 结果当基准

## 护栏

- 凡 VM 内跑 NTP 服务，必须只有一个时钟写入者；代理的改时钟能力剥离在 `ansible/playbooks/tasks/ntp.yaml`，drift 重置在其 handler 与 `ansible/playbooks/setup-time.yaml`
- 时钟类修复必须做重启回归：被污染的 drift 与内核状态会持久化，重启后不再出现步进、`sync=1`、无 maxerror 尖峰才算修复
- 告警 `NodeClockNotSynchronising` 与 `node_timex_maxerror_seconds >= 16` 同时出现时，先查虚拟化同步代理，不要先换 NTP 源
- 宿主 `timed` 的自由游走是已知行为；无法写进代码：stock `timed` 不做连续锁相，无法用配置保证 <100ms，收敛只能换 chrony
