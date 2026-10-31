# Lima on Mac mini 虚拟机配置

参考配置：[`lima/sakamoto.yaml`](../lima/sakamoto.yaml)

## 桥接网络配置

启用物理局域网桥接需预先编译安装 [socket_vmnet](https://lima-vm.io/docs/config/network/vmnet/)：

```bash
git clone https://github.com/lima-vm/socket_vmnet
cd socket_vmnet
# 检出最新 release tag（或参考 https://github.com/lima-vm/socket_vmnet/releases）
git checkout $(git describe --tags $(git rev-list --tags --max-count=1))
make
sudo make PREFIX=/opt/socket_vmnet install.bin
# Set up the sudoers file for launching socket_vmnet from Lima
limactl sudoers >etc_sudoers.d_lima
less etc_sudoers.d_lima  # verify that the file looks correct
sudo install -o root etc_sudoers.d_lima /etc/sudoers.d/lima
rm etc_sudoers.d_lima
```

在 Lima 配置文件中指定桥接网卡与 MAC 地址：

```yaml
networks:
- lima: bridged
  interface: eth1
  macAddress: "52:55:55:37:34:56"
```

固定 MAC 地址以确保 IP 稳定（寻址由 Lima 经 cloud-init 下发，见 ADR-0001）

## 数据盘配置

将 Lima 虚拟磁盘存储目录软链接至外置高速存储：

```bash
# 将lima的硬盘位置软链接到外置ssd
rm -rf ~/.lima/_disks
mkdir -p /Volumes/sakamoto-data/k8s/lima/_disks && ln -s /Volumes/sakamoto-data/k8s/lima/_disks ~/.lima/_disks

# 创建硬盘 默认ext4格式
limactl disk create longhorn --size 1024G
```

在配置里加上（`format: false` 不可省：Lima 会把脏盘当未初始化盘做 mkfs，覆盖 Longhorn 数据；被覆盖后的磁盘重新纳入见 [运维笔记的 Longhorn 小节](operations-notes.md#longhorn)）

```yaml
additionalDisks:
  - name: "longhorn"
    format: false
```

## 网络与磁盘变更注意

- 改网络前先列 `/etc/netplan/` 全部文件并确认每个文件的写入方：Lima 节点的接口命名、寻址与 `route-metric` 由 Lima 经 cloud-init 下发，Ansible 只写 DNS drop-in 与 VLAN，见 [ADR-0001](adr/0001-lima-network-ownership.md)。netplan 会合并所有文件，同一接口上静态与 DHCP 配置并存会造成默认路由冲突、桥接地址消失
- 改完用 `ls /etc/netplan/`、`ip -br a`、`ip route`、`netplan get` 四者一致核对，`limactl list` 显示 Running 不代表 guest 网络就绪
- 用 `ip -d link` 区分接口名与 altname：`enp0s1` 可能只是 `eth0` 的 altname，看到 `renamed from` 不要直接判定接口改名
- 离线挂载 guest 磁盘前必须先停 VM，运行中挂载会造成 ext4 损坏
- 单控制面场景下，未定位根因不得重启宿主机，重启会打断取证并延长中断
