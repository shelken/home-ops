# Proxmox 创建虚拟机

GPU worker 是 PVE 虚拟机，系统由 nix-config 声明并用 nixos-anywhere 安装，见 nix-config 的 `hosts/k8s/README.md`，不再使用云镜像模板与 cloud-init。PVE 侧只需要准备空虚拟机：UEFI（`--bios ovmf`）、`q35`、`--cpu host`、virtio 网卡与磁盘、`--agent 1`

## GPU 直通相关设置

```bash
export VM_ID=<VM_ID>

## 关键启动参数，避免驱动安装失败
qm set $VM_ID --args "-cpu host,kvm=off"
## 关闭虚拟显示输出
qm set $VM_ID --vga none
## Intel 核显直通
qm set $VM_ID --hostpci0 0000:00:02,pcie=1,rombar=0
## NVIDIA vGPU（mdev profile 见 15-gpu.md）
qm set $VM_ID --hostpci1 0000:01:00.0,mdev=nvidia-49,pcie=1,rombar=0
```
