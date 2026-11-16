# GPU

> PVE 虚拟化环境下的显卡驱动安装、vGPU 分配与直通配置

## NVIDIA

### vGPU 虚拟化

- [vGPU 驱动安装与补丁教程](https://gitlab.com/polloloco/vgpu-proxmox)
- [自建 fastapi-dls 授权许可服务](https://git.collinwebdesigns.de/oscar.krause/fastapi-dls)
- [fastapi-dls Docker Hub 镜像](https://hub.docker.com/r/collinwebdesigns/fastapi-dls)
- [vGPU 驱动网盘资源（佛西网盘）](https://alist.homelabproject.cc/foxipan/vGPU/16.8)
- [英伟达官方驱动归档](https://www.nvidia.com/en-us/drivers/)

#### 宿主机

根据教程，宿主机安装patch之后的driver、 解锁消费级显卡、 覆盖配置要使用的profile

17.0开始 Pascal系列的架构除了需要下面的patch，还需要将16.x的vgpuConfig.xml文件替换掉17.x的

目前稳定使用17.6没有问题. 旧的16.8也测试正常

```bash
# 根据所选 vGPU 驱动版本设置变量
export VGPU_DRIVER_VERSION="<VGPU_DRIVER_VERSION>"
./NVIDIA-Linux-x86_64-${VGPU_DRIVER_VERSION}-vgpu-kvm.run --apply-patch ~/vgpu-proxmox/${VGPU_DRIVER_VERSION}.patch
./NVIDIA-Linux-x86_64-${VGPU_DRIVER_VERSION}-vgpu-kvm-custom.run --dkms -m=kernel
```

宿主机覆盖的配置示例

```toml
[profile.nvidia-49]
num_displays = 1          # Max number of virtual displays. Usually 1 if you want a simple remote gaming VM
display_width = 1920      # Maximum display width in the VM
display_height = 1080     # Maximum display height in the VM
max_pixels = 2073600      # This is the product of display_width and display_height so 1920 * 1080 = 2073600
cuda_enabled = 1          # Enables CUDA support. Either 1 or 0 for enabled/disabled
frl_enabled = 1           # This controls the frame rate limiter, if you enable it your fps in the VM get locked to 60fps. Either 1 or 0 for enabled/disabled
framebuffer = 0xEC000000
framebuffer_reservation = 0x14000000
```

#### vm

虚拟机里的 vGPU guest 驱动与 `nvidia` 容器运行时由 nix-config 声明，见 nix-config 的 `modules/features/homelab/k3s-nvidia-vgpu/README.md`。驱动版本、内核固定原因与授权令牌的位置都在那里

#### 授权激活（fastapi-dls）

授权服务 `fastapi-dls` 以 Docker Compose 运行在宿主机 sakamoto，服务名 `nvidia-dls`，定义见 nix-config: `hosts/sakamoto/apps/compose.yaml`。client token 存在节点的 sops 文件里，由 nix-config 部署并启用 `nvidia-gridd`，不再手动获取。在 VM 中检查：

```bash
sudo nvidia-smi -q | grep -i lic
# 使用ffmpeg测试
ffmpeg -hwaccel cuda -i ~/EP05_01m.mp4 -f null -
```

### VM 显卡直通

> 笔记本架构的GPU直通还是有问题。一直 no device found. 即使驱动看起来都正常
>
> 在系统2410, 2404，。各种版本 535 550 570 都试过，没用。跟romfile或者NVIDIA的限制可能有关

### LXC

> 放弃在lxc上弄k3s，会有大量问题。至少在vm

```bash
./NVIDIA-Linux-x86_64-535.247.01.run --no-kernel-module
```

### 节点标签分配

工作节点 GPU 标签由 nix-config 的 `hosts/k8s/homelab-1/default.nix` 声明（`shelken.k3s.nodeLabels`），无需手动执行 `kubectl label`

## INTEL

### 添加gpu到vm

在完成 pve 直通 intel gpu 的操作之后，给 vm 添加 pci。VM 内的固件与驱动由 nix-config 声明，见 `hosts/k8s/homelab-1/default.nix`。检查：

```bash
# 确保存在 renderD128
ls -la /dev/dri
lspci -nnk | grep -B5 i915
```

### Intel 核显标签分配

标签 `intel.feature.node.kubernetes.io/gpu=true` 同样由 nix-config 声明
