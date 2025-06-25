
## 链接

- [Proxmox VE - How to build an Ubuntu 22.04 Template (Updated Method)](https://www.youtube.com/watch?v=MJgIm03Jxdo)
- [示例vm文件](resource/proxmox-vm-template-example.conf)

## 流程

1. 在webui创建一个基本的vm
2. 下载ubuntu官方的cloud image
3. 命令：

22.04-minimal

```shell
wget https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img
mv ubuntu-22.04-minimal-cloudimg-amd64.img ubuntu-2204.qcow2
qemu-img info ubuntu-2204.qcow2
# 调整下磁盘大小
qemu-img resize ubuntu-2204.qcow2 25G
# 允许在webui查看显示输出
qm set 1002 --serial0 socket --vga serial0

qm importdisk 1002 ubuntu-2204.qcow2 local-lvm

```

24.10-server oracular

```shell
wget https://cloud-images.ubuntu.com/releases/oracular/release/ubuntu-24.10-server-cloudimg-amd64.img
mv ubuntu-24.10-server-cloudimg-amd64.img ubuntu-24.10.qcow2
qemu-img info ubuntu-24.10.qcow2
qemu-img resize ubuntu-24.10.qcow2 25G
qm importdisk 1100 ubuntu-24.10.qcow2 local-lvm
qm set 1100 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-1100-disk-0

qm template 1100
```

4. 设置cloud init
5. 将刚才的disk放在第一位顺位开启。
6. 启动

```shell
apt install qemu-guest-agent
ip a

# 克隆 1002 模板 成新的110实例
qm clone 1002 110 --name test-ubuntu-1
qm clone 1002 111 --name test-ubuntu-2
qm clone 1002 112 --name test-ubuntu-3

# 静态ip
qm set 110 --ipconfig0 ip=192.168.6.110/24,gw=192.168.6.1
qm set 111 --ipconfig0 ip=192.168.6.111/24,gw=192.168.6.1
qm set 112 --ipconfig0 ip=192.168.6.114/24,gw=192.168.6.1

# 用ssh尝试连接

```

