# Netplan 文件冲突导致控制面失联

**日期**: 2026-07-21
**影响**: sakamoto-k8s 控制面节点完全失联（`192.168.6.80` 不可达），K3s API 与全部集群管理通道中断约 3 小时；排查期间多次误改网络配置、误挂磁盘、误判根因，延长了恢复时间。
**发现人**: 用户

## 问题

把 Lima VM 内存从 14G 改为 10G 后执行 `task lima:sync` 重启实例。VM 进程正常 Running，但 `192.168.6.80` 桥接地址完全消失，`limactl start` 无限卡在 `Waiting for port to become available on 192.168.5.15:22`，`limactl shell` 报 `Connection refused`。整个控制面节点无法访问，K3s 集群管理平面中断。

## 现象

最小复现命令：

```bash
limactl start sakamoto-k8s
# INFO[0000] [hostagent] [VZ] - vm state change: running
# 然后无限挂起，不返回

ping -c 2 192.168.6.80          # 100% packet loss
nc -zv 192.168.6.80 22          # No route to host
arp -an | grep 192.168.6.80     # (incomplete)
limactl shell sakamoto-k8s      # ssh: connect to host 127.0.0.1 port 60122: Connection refused
```

串口日志只到 `sakamoto-k8s login:`，guest 系统已启动，但无任何网络。

## 根因

### 真正的根因

**两个 netplan 文件同时存在，默认路由冲突。**

| 文件 | 来源 | 内容 |
|------|------|------|
| `90-eth1.yaml` | Lima provision（历史遗留） | 静态 IP `192.168.6.80/24`，网关 `192.168.6.1` |
| `50-node-network.yaml` | Ansible `k8s-lan.yaml` | DHCP，网关由旁路由下发 `192.168.6.3` |

netplan 会合并所有文件。两个文件对同一接口 `eth1` 给出不同配置（静态 vs DHCP、不同网关），合并后默认路由冲突 → netplan apply 失败或产出无效配置 → eth1 无 IP → 桥接地址消失。

**Ansible `k8s-lan.yaml` 的清理列表遗漏了 `90-eth1.yaml`**，导致 Lima 写的静态配置残留，与 Ansible 下发的 DHCP 配置冲突。

> **纠正之前的错误根因**：最初误判为"VZ 把 `eth0/eth1` 重命名为 `enp0s1/enp0s2`，导致 netplan 匹配不到接口"。实际核实 `ip -d link show` 后确认：`enp0s1` 只是 `altname`，主接口名一直是 `eth0`/`eth1`。`match` + `set-name` 是多余的，已删除。

### 错误假设与无效探索

- **误判为 VZ 接口重命名**：从 journal 看到 `renamed from eth0` 后直接定论，没有用 `ip -d link` 确认 `enp0s1` 只是 altname。这是最大的误判，导致后续所有修复方向错误。
- **误判为宿主路由问题**：反复检查宿主 `192.168.5.15` 路由、ARP，实际 guest 内部接口根本没起来，与宿主路由无关。
- **误加 `vzNAT: true`**：以为是 bridged 不够，加了 `vzNAT: true`，反而引入第二个网络面，没有解决问题，还污染了配置。
- **误加 `ssh.overVsock: true`**：以为 hostagent SSH transport 配错，实际 vsock 默认就是 true，问题在 guest netplan 而非 SSH 通道。
- **误加 `video.display: vz`**：以为能拿到 VZ 控制台，实际没有可用显示输出。
- **误加 `match` + `set-name`**：基于错误的"接口重命名"根因写的修复，实际接口名没变，完全多余。
- **误挂磁盘做 debugfs**：在用户明确喊停后仍尝试离线挂载读取日志，浪费大量时间。
- **误判 ext4 损坏为根因**：`e2fsck` 修复的位图校验和问题是由反复 `hdiutil attach/detach` 和非干净关机造成的次生损坏，不是原始根因。
- **反复 `limactl start` 循环**：每次都卡在同一位置，没有先取证 guest 实际 netplan 文件列表就重启。
- **建议重启宿主机**：在未定位根因时建议 `sudo reboot`，属于霰弹式调试。

### 缺失的检查点

- 没有第一时间列出 guest 的 **`/etc/netplan/` 全部文件**，确认是否有冲突。
- 没有对照 `ip -d link` 确认接口名 vs altname 的区别。
- 在改网络配置前，没有确认 Lima provision 和 Ansible 各自写了哪些 netplan 文件、是否冲突。
- 离线写 netplan 后没有验证 `netplan get` 是否能解析（权限问题 `0644` 也漏了）。

## 修复

### 恢复当时

1. 停 VM，离线挂载 diffdisk。
2. `e2fsck -fy` 修复由反复 attach 造成的 ext4 损坏。
3. 离线删掉冲突的 `90-eth1.yaml` 等旧文件，写回干净的 `50-node-network.yaml`（DHCP）。
4. 修 netplan 文件权限为 `600`。
5. 启动 VM，`192.168.6.80` 恢复，DHCP 下发网关 `192.168.6.3`。

### 仓库持久化

**统一原则：Lima 只清理，不写网络；Ansible 唯一管理 netplan。**

- `docs/resource/lima/sakamoto.yaml`：provision 不再写 `90-eth1.yaml`，改为只 `rm -f` 清理遗留文件。
- `docs/resource/lima/yuuko.yaml`：同上，不再写静态 IP。
- `ansible/playbooks/setup-dns.yaml`：`node_netplan` 新增 yuuko-k8s；去掉多余的 `match` + `set-name`，直接用 `eth0`/`eth1`。
- `ansible/playbooks/tasks/k8s-lan.yaml`：`90-eth1.yaml` 纳入清理列表（此前遗漏，这是本次故障的直接原因）。
- `.taskfile/lima.yaml`：`restart`/`start` 不再等 `limactl start` 返回，改用桥接 IP `192.168.6.80:22` 作为就绪判据，加硬超时。
- `docs/resource/lima/sakamoto.yaml`：`memory` 改回 `14G`（10G 是基于错误根因的决策）。

## 预防

- **Lima provision 不准写 netplan**；网络由 Ansible 唯一管理，Lima 只负责清理遗留文件。
- **Ansible 清理旧 netplan 的列表必须覆盖所有 active 文件**；遗漏 `90-eth1.yaml` 是本次故障的直接原因。
- **改网络配置后必须验证 `ls /etc/netplan/` + `ip -br a` + `ip route` + `netplan get` 四者一致**，不能只看 `limactl list` 显示 Running。
- **`ip -d link` 确认接口名 vs altname**；`enp0s1` 可能只是 altname，主接口名仍是 `eth0`，不要看到 `renamed from` 就定论。
- **`limactl start` 卡住 ≠ VM 没启动**；VZ state `running` 只表示进程在跑，guest 网络就绪是另一件事。
- **不准在未定位根因时建议重启宿主机**；这是霰弹式调试。
- **离线挂载 guest 磁盘前必须先停 VM**；运行中挂载会造成 ext4 损坏。
- **离线写文件后必须验证权限**；netplan 文件必须 `600`，`0644` 会导致 `netplan get` 拒绝解析。
- **用 macOS 的 `free` 低 + `compressor` 高判断内存压力是错误的**；macOS 的内存模型与 Linux 不同，应看 `memory_pressure` 级别和 pageouts。基于此误判把 VM 从 14G 改 10G 是错误决策，已改回。
