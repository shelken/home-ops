# Proxmox 创建虚拟机

## 链接

- [Proxmox VE - How to build an Ubuntu 22.04 Template (Updated Method)](https://www.youtube.com/watch?v=MJgIm03Jxdo)

## Ubuntu 24.04 Server (Noble)

选择版本时需确认内核版本与当前集群匹配，参考 Ubuntu 官方 [发布历史](https://ubuntu.com/about/release-cycle#ubuntu-kernel-release-cycle)

### 下载镜像

```bash
ssh pve

cd /var/lib/vz/template/iso

wget -c https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img -O ubuntu-24.04-server-cloudimg-amd64.img

## 完整性校验与格式转换
wget -qO- https://cloud-images.ubuntu.com/releases/noble/release/SHA256SUMS | grep ubuntu-24.04-server-cloudimg-amd64.img | sha256sum -c

mv ubuntu-24.04-server-cloudimg-amd64.img ubuntu-24.04.qcow2
qemu-img info ubuntu-24.04.qcow2
qemu-img resize ubuntu-24.04.qcow2 32G

```

### 创建虚拟机模板

```bash
export TEMPLATE_ID=1800
export TEMPLATE_NAME=ubuntu-24-04-homelab-template
export TEMPLATE_CI_USER="<CI_USER>"
export TEMPLATE_CI_PASS="<CI_PASSWORD>"
export SSH_PUBLIC_KEY="<SSH_PUBLIC_KEY>"

# 说明：
# 使用 net1 而不是 net0 可生成 eth1 设备名，与 Lima 虚拟网卡设备命名保持统一
# 执行 `qm cloudinit dump 110 network` 可提前验证生成的网络配置
qm create $TEMPLATE_ID \
  --name $TEMPLATE_NAME \
  --bios ovmf \
  --machine q35 \
  --ostype l26 \
  --cpu host \
  --cores 1 \
  --sockets 1 \
  --memory 2048 \
  --numa 0 \
  --scsihw virtio-scsi-single \
  --efidisk0 local-lvm:4,efitype=4m,pre-enrolled-keys=0 \
  --scsi1 local-lvm:cloudinit \
  --net1 virtio,bridge=vmbr0 \
  --agent 1 \
  --serial0 socket \
  --ciuser "$TEMPLATE_CI_USER" \
  --cipassword $(openssl passwd -5 "$TEMPLATE_CI_PASS") \
  --ciupgrade 0 \
  --sshkeys <(echo "$SSH_PUBLIC_KEY")

```


```bash
## 导入磁盘与转为模板
qm importdisk $TEMPLATE_ID ubuntu-24.04.qcow2 local-lvm

# 普通hdd
qm set $TEMPLATE_ID --scsi0 "local-lvm:vm-$TEMPLATE_ID-disk-1,ssd=0,discard=on,iothread=1,aio=io_uring,cache=none"
# or ssd 优化
qm set $TEMPLATE_ID --scsi0 "local-lvm:vm-$TEMPLATE_ID-disk-1,ssd=1,discard=on,iothread=1,aio=io_uring,cache=none"

qm set $TEMPLATE_ID --boot order=scsi0

qm template $TEMPLATE_ID
```

### 克隆并启动工作节点实例

```bash
export CURRENT_VM_ID=110

# 克隆模板（$TEMPLATE_ID=1800）为新的 110 节点实例
qm clone $TEMPLATE_ID $CURRENT_VM_ID --name "homelab-$CURRENT_VM_ID"

# 静态ip
qm set $CURRENT_VM_ID --ipconfig1 ip=192.168.6.110/24,gw=192.168.6.1

# cpu, memory, resize
qm set $CURRENT_VM_ID --cores 4
qm set $CURRENT_VM_ID --memory 14336
qm disk resize $CURRENT_VM_ID scsi0 +300G

# GPU 直通配置
## 关键启动参数，避免驱动安装失败
qm set $CURRENT_VM_ID --args "-cpu host,kvm=off"
## 关闭虚拟显示输出
qm set $CURRENT_VM_ID --vga none
## Intel 核显直通
qm set $CURRENT_VM_ID --hostpci0 0000:00:02,pcie=1,rombar=0
## NVIDIA 显卡直通
qm set $CURRENT_VM_ID --hostpci1 0000:01:00.0,mdev=nvidia-49,pcie=1,rombar=0
# 用ssh尝试连接

qm start $CURRENT_VM_ID
qm terminal $CURRENT_VM_ID
```


### Cloud-Init 磁盘维护

若原有接口为 ide0，可切换为 scsi 接口：

```bash
qm set $CURRENT_VM_ID --delete ide0
qm set $CURRENT_VM_ID --scsi1 local-lvm:cloudinit
```
