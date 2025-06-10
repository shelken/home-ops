
## 链接

- [Proxmox VE - How to build an Ubuntu 22.04 Template (Updated Method)](https://www.youtube.com/watch?v=MJgIm03Jxdo)
- [示例vm文件](resource/proxmox-vm-template-example.conf)

## 流程

1. 在webui创建一个基本的vm
2. 下载ubuntu官方的cloud image
3. 命令：

```shell
wget https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img
# 调整下磁盘大小
qemu-img resize ubuntu-2204.qcow2 20G
# 允许在webui查看显示输出
qm set 1002 --serial0 socket --vga serial0

qm importdisk 1002 ubuntu-2204.qcow2 local-lvm

```

4. 设置cloud init
5. 将刚才的disk放在第一位顺位开启。
6. 启动

```shell
apt install qemu-guest-agent
ip a

# 完全克隆 1002 模板 成新的110实例
qm clone 1002 110 --name test-ubuntu-2

# 静态ip

# 用ssh尝试连接

```

