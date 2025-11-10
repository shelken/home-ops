
## 链接

- [Proxmox VE - How to build an Ubuntu 22.04 Template (Updated Method)](https://www.youtube.com/watch?v=MJgIm03Jxdo)
- [示例vm文件](resource/proxmox-vm-template-example.conf)

## 24.04-server noble

> [!note] 选择版本时需注意内核版本是否与当前集群匹配
>
> 可以看Ubuntu的官方的内核 [发布历史](https://ubuntu.com/about/release-cycle#ubuntu-kernel-release-cycle)

### download image

```shell
ssh pve

cd /var/lib/vz/template/iso

wget -c https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img -O ubuntu-24.04-server-cloudimg-amd64.img

## 检查完整
wget -qO- https://cloud-images.ubuntu.com/releases/noble/release/SHA256SUMS | grep ubuntu-24.04-server-cloudimg-amd64.img | sha256sum -c

mv ubuntu-24.04-server-cloudimg-amd64.img ubuntu-24.04.qcow2
qemu-img info ubuntu-24.04.qcow2
qemu-img resize ubuntu-24.04.qcow2 32G

```

### 创建 VM template

```shell
export TEMPLATE_ID=1800
export TEMPLATE_NAME=ubuntu-24-04-homelab-template
export TEMPLATE_CI_PASS=xxxxxxxx
export MIO_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN9sMBAahOZKZ5QXBEsu6ACfgX8TSt5EgD+E1h6mtzG2 shelken@mio"

# note
# 使用 net1 而不是 net0 可以生成 eth1 设备名（期望与lima的设备统一）
# 可以使用`qm cloudinit dump 110 network`提前验证生成的network
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
  --scsihw virtio-scsi-pci \
  --efidisk0 local-lvm:4,efitype=4m,pre-enrolled-keys=0 \
  --ide0 local-lvm:cloudinit \
  --net1 virtio,bridge=vmbr0,firewall=1 \
  --agent 1 \
  --serial0 socket \
  --ciuser shelken \
  --cipassword $(openssl passwd -5 "$TEMPLATE_CI_PASS") \
  --ciupgrade: 0 \
  --sshkeys <(echo "$MIO_KEY") \
  --nameserver "192.168.6.141 192.168.6.1 223.5.5.5"

```


```shell
## disk 操作
qm importdisk $TEMPLATE_ID ubuntu-24.04.qcow2 local-lvm
qm set $TEMPLATE_ID --scsi0 "local-lvm:vm-$TEMPLATE_ID-disk-1,cache=writethrough"
qm set $TEMPLATE_ID --boot order=scsi0

qm template $TEMPLATE_ID
```

6. 启动

```shell
export CURRENT_VM_ID=110

# 克隆 1002 模板 成新的110实例
qm clone $TEMPLATE_ID $CURRENT_VM_ID --name "homelab-$CURRENT_VM_ID"

# 静态ip
qm set $CURRENT_VM_ID --ipconfig1 ip=192.168.6.110/24,gw=192.168.6.1

# cpu, memory, resize
qm set $CURRENT_VM_ID --cores 4
qm set $CURRENT_VM_ID --memory 14336
qm disk resize $CURRENT_VM_ID scsi0 +300G

# gpu
## 很重要的启动参数，不然driver安装不了
qm set $CURRENT_VM_ID --args "-cpu host,kvm=off"
## 不要给显示器显示
qm set $CURRENT_VM_ID --vga none
## intel
qm set $CURRENT_VM_ID --hostpci0 0000:00:02,pcie=1,rombar=0
## nvidia
qm set $CURRENT_VM_ID --hostpci1 0000:01:00.0,mdev=nvidia-49,pcie=1,rombar=0

# 用ssh尝试连接

qm start $CURRENT_VM_ID
qm terminal $CURRENT_VM_ID
```
