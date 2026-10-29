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

在配置里加上（`format: false` 不可省：Lima 会把脏盘当未初始化盘做 mkfs，覆盖 Longhorn 数据，见 [postmortems/019](../postmortems/019-lima-dirty-disk-mkfs-destroys-longhorn.md)）

```yaml
additionalDisks:
  - name: "longhorn"
    format: false
```
