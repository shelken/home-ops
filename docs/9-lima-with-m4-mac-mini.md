# lima

[sakamoto 配置文件](/docs/resource/lima/sakamoto.yaml)

## 网络

需要桥接网络的话，安装[socket_vmnet](https://lima-vm.io/docs/config/network/vmnet/)

```shell
git clone https://github.com/lima-vm/socket_vmnet
cd socket_vmnet
# Change "v1.2.1" to the actual latest release in https://github.com/lima-vm/socket_vmnet/releases
git checkout v1.2.1
make
sudo make PREFIX=/opt/socket_vmnet install.bin
# Set up the sudoers file for launching socket_vmnet from Lima
limactl sudoers >etc_sudoers.d_lima
less etc_sudoers.d_lima  # verify that the file looks correct
sudo install -o root etc_sudoers.d_lima /etc/sudoers.d/lima
rm etc_sudoers.d_lima
```

配置文件里加上

```yaml
networks:
- lima: bridged
  interface: lima1
  macAddress: "52:55:55:37:34:56"
```

第一次进入之后记下macAddress, 或者自定义一个，然后固定。使用路由器给MAC地址分配固定ip

## 添加硬盘

```shell
# 将lima的硬盘位置软链接到外置ssd
rm -rf ~/.lima/_disks
mkdir -p /Volumes/sakamoto-data/k8s/lima/_disks && ln -s /Volumes/sakamoto-data/k8s/lima/_disks ~/.lima/_disks

# 创建硬盘 默认ext4格式
limactl disk create longhorn --size 1024G
```

在配置里加上

```yaml
additionalDisks:
  - "longhorn"
```