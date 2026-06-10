# 群晖磁盘恢复流程

从黑群晖坏掉的磁盘中恢复数据，通过 Lima VM 直接挂载物理磁盘并读取 md RAID / LVM / btrfs（或 ext4）文件系统。

## 前置条件

需要 Lima >= v2.2.0 才支持 `blockDevices`（VZ 驱动下直通宿主块设备）。目前最新 stable 只有 v2.1.2，需临时切换到 CI 构建。

```bash
# 切到 CI 构建（一次性，恢复完可 revert）
lima-switch install <ci-解压目录>
lima-switch status
# 恢复后：
# lima-switch revert
```

`lima-switch` 脚本在 `scripts/lima-switch.sh`，用法就是上面三行。
等价于在 `$PATH` 下放个可执行脚本，核心是把 CI 产物复制到 Cellar 新 keng 并改软链接。

## 配置文件

`docs/resource/lima/recovery.yaml`

```yaml
vmType: "vz"
cpus: 2
memory: 2G
disk: 20G

blockDevices:
  - /dev/diskX   # ← 替换为群晖磁盘实际设备号（diskutil list external physical 确认）

ssh:
  localPort: 60124
images:
  # 固定版本号 + digest，只下载一次，后续复用缓存
  - location: "https://cloud-images.ubuntu.com/releases/noble/release-20260518/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"
    digest: "sha256:6a61b967ba4a27dd1966f835a67643073ed55c2860ce3dc1cb0517282e6b8bec"
```

## 踩过的坑

### 必须使用 CI 构建（>= v2.2.0）

`blockDevices` 在 v2.2.0 才合入，当前 brew stable 只有 v2.1.2。

```bash
# 用 lima-switch 临时切到 CI 构建
lima-switch install <ci-解压目录>
# 恢复后：
lima-switch revert
```

### 镜像要用固定版本 + digest

不带 `digest` 的 `release/` 链接是滚动发布，每次启动都会去对比上游，一更新就重下。

```yaml
# ❌ 每次重下
images:
  - location: ".../noble/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"

# ✅ 固定版本 + digest，只下一次
images:
  - location: ".../noble/release-20260518/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"
    digest: "sha256:6a61b967..."
```

### blockDevices 需要 sudoers

`blockDevices` 依赖 `sudo-open-block-device` helper 以 root 获取块设备 fd 再传给无 root 的 VM 进程。
光有 bridged 网络的 sudoers 规则不够，需要追加 block-device 条目：

```bash
limactl sudoers | sudo tee /etc/sudoers.d/lima
```

这不会覆盖已有的网络规则，只会追加新条目。

### 单盘 inactive spare 无法 assemble

群晖 SHR-1 缺盘后，mdadm 把剩余盘标记为 spare（`(S)`），`--assemble --scan` 直接跳过。

```bash
cat /proc/mdstat
# md127 : inactive vdb3[0](S)
#       971940560 blocks super 1.2

sudo mdadm --assemble /dev/md3 /dev/vdb3 --run --force
# → No suitable drives found
```

`--examine` 看细节：

```bash
sudo mdadm --examine /dev/vdb3 | grep -E "Raid Level|Raid Devices|Device Role|Array State"
# Raid Level : raid1
# Raid Devices : 1
# Device Role : Active device 32768
# Array State : .    ← 成员不活跃，mdadm 拒绝组
```

**解法：绕过 mdadm，用 `losetup` + offset 直接读 LVM/btrfs**

```bash
# Data Offset (单位为 sector，1 sector = 512 bytes)
sudo losetup --find --show --read-only --offset $((2048*512)) /dev/vdb3
# → /dev/loop0
```

然后检查是否有 LVM：

```bash
sudo pvscan
# 可能有输出，也可能没有——群晖单盘 SHR 有时不套 LVM，直接是 btrfs/ext4
```

如果没有 LVM 输出，btrfs 直接在 loop 设备上：

```bash
sudo blkid /dev/loop0
# TYPE="btrfs"
sudo mount -t btrfs -o ro /dev/loop0 /mnt/raid
```

### 文件权限

挂载后文件属主是数字 uid（如 1026），不是当前用户名。

```bash
ls -lah /mnt/raid
# drwxrwxrwx 1 1026 users  188 Sep  8  2022 Video
```

解决：用 `sudo` 或 `sudo -i` 切 root 操作。rsync 时可以保留 uid/gid 让 macOS 忽略（`--no-owner --no-group`）。

## 操作步骤

### 1. 插入磁盘并确认设备号

```bash
diskutil list external physical
```

### 2. 修改模板中的设备号

```bash
vim /tmp/recovery.yaml
# 把 blockDevices 下的 /dev/diskX 改成上一步看到的实际值
```

### 3. 启动 Lima VM

```bash
limactl start /tmp/recovery.yaml --name=recovery
```

### 4. 进入 VM，确认磁盘已透传

```bash
limactl shell recovery
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
```

群晖数据分区一般是 `vdb3`（前两个 `vdb1/vdb2` 是系统分区）。

### 5. 识别阵列元数据

```bash
sudo mdadm --examine /dev/vdb3 | grep -E "Raid Level|Raid Devices|Data Offset|Device Role|Array State"
```

如果 `Array State` 是 `.` 且 `(S)` inactive（见上方踩坑记录），直接跳到步骤 6 走 losetup 绕过。

### 6. 绕过 mdadm，losetup 直读

```bash
# 用 Data Offset 字段的值（单位 sector，1 sector = 512 bytes）
sudo losetup --find --show --read-only --offset $((2048*512)) /dev/vdb3
# → /dev/loop0

# 看文件系统类型
sudo blkid /dev/loop0
# TYPE="btrfs" 或 TYPE="ext4"

# 检查是否有 LVM（单盘 SHR 通常直接是 btrfs，无 LVM）
sudo pvscan
```

### 7. 只读挂载

```bash
sudo mkdir -p /mnt/raid

# btrfs
sudo mount -t btrfs -o ro /dev/loop0 /mnt/raid
# 或 ext4
# sudo mount -t ext4 -o ro,noload /dev/loop0 /mnt/raid
```

### 8. 浏览数据

```bash
sudo ls -lah /mnt/raid
sudo find /mnt/raid -maxdepth 2 -type d | head -80
```

### 9. 从 macOS 拉取数据

```bash
# dry-run
rsync -avhn --itemize-changes --protect-args \
  --exclude='*/@eaDir/' \
  --exclude='*/#recycle/' \
  -e 'ssh -p 60124' \
  localhost:/mnt/raid/<path> <local-target>

# 真复制
rsync -avhP --info=progress2 --protect-args \
  --exclude='*/@eaDir/' \
  --exclude='*/#recycle/' \
  -e 'ssh -p 60124' \
  localhost:/mnt/raid/<path> <local-target>
```

## 绝对不能做的事

```bash
# 不要创建新阵列（会覆盖元数据）
mdadm --create

# 不要文件系统检查修复
fsck -y
btrfs check --repair

# 不要读写挂载
mount <device> <path>     # 必须加 -o ro
```

## 恢复后清理

```bash
limactl stop recovery
limactl rm recovery
lima-switch revert          # 切回 brew 原版
diskutil eject /dev/diskX  # 安全弹出磁盘
```
