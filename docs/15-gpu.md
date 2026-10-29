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

然后虚拟机vm安装相关包和驱动

```bash
ansible-playbook ansible/playbooks/install-nvidia.yaml
```

```bash
# rsync 传输驱动安装文件（版本以 ansible/playbooks/install-nvidia.yaml 为准）
export GRID_DRIVER_VERSION="<GRID_DRIVER_VERSION>"
rsync -avzP "NVIDIA-Linux-x86_64-${GRID_DRIVER_VERSION}-grid.run" <SSH_USER>@192.168.6.111:~/

sudo ./NVIDIA-Linux-x86_64-${GRID_DRIVER_VERSION}-grid.run --silent --no-questions --accept-license --disable-nouveau
```

#### 授权激活（fastapi-dls）

授权服务 `fastapi-dls` 以 Docker Compose 运行在宿主机 sakamoto，服务名 `nvidia-dls`，定义见 [`compose/sakamoto/docker-compose.yml`](../compose/sakamoto/docker-compose.yml)。在 VM 中获取 client token 并启用 `nvidia-gridd`：

```bash
export MAIN_DOMAIN=
sudo curl --insecure -L -X GET https://nvidia-dls.$MAIN_DOMAIN/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_$(date '+%d-%m-%Y-%H-%M-%S').tok
sudo systemctl enable --now nvidia-gridd
sudo reboot

# 检查
sudo nvidia-smi -q | grep -i lic
# 使用ffmpeg测试
ffmpeg -hwaccel cuda -i ~/EP05_01m.mp4 -f null -
```

### VM 显卡直通

> 笔记本架构的GPU直通还是有问题。一直 no device found. 即使驱动看起来都正常
>
> 在系统2410, 2404，。各种版本 535 550 570 都试过，没用。跟romfile或者NVIDIA的限制可能有关

UEFI情况下，VM关闭「安全启动」

然后进入安装

```bash
# 列出当前系统可用分支，选择已验证分支安装（如 570-server 验证通过）
apt-cache search --names-only '^nvidia-headless-[0-9]+-server$'
sudo apt install nvidia-headless-<BRANCH>-server
sudo reboot
```

安装driver后VM中检查：

```bash
lsmod | grep nvid
lspci -nnk | grep -A5 NVI
# ffmpeg
ffmpeg -decoders | grep cuvid
```

https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#with-apt-ubuntu-debian
[k3s中配置nvidia-container-toolkit](https://docs.k3s.io/advanced#nvidia-container-runtime)

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt install -y nvidia-container-runtime
sudo reboot
```

### LXC

> 放弃在lxc上弄k3s，会有大量问题。至少在vm

```bash
./NVIDIA-Linux-x86_64-535.247.01.run --no-kernel-module
```

### 节点标签分配

当前工作节点 GPU 标签已由 Ansible 声明式管理（见 [`ansible/inventory/host_vars/homelab-1.yaml`](../ansible/inventory/host_vars/homelab-1.yaml)），无需手动执行 `kubectl label`

## INTEL

### 添加gpu到vm

在完成pve直通intel gpu的一些操作之后，给vm添加pci

```bash
# 然后确保存在 renderD128
ls -la /dev/dri

# ubuntu cloudimage缺少相关i915的加载 需要安装
sudo apt install linux-modules-extra-$(uname -r)
sudo apt install linux-firmware
```

检查

```bash
lspci -nnk | grep -B5 i915
```

### Intel 核显标签分配

同上，已由 Ansible 自动分配标签 `intel.feature.node.kubernetes.io/gpu=true`

### 宿主机内核模块配置

```bash
# 手动加载模块
sudo modprobe i915

# 设置开机自动加载
echo "i915" | sudo tee -a /etc/modules

# 更新 initramfs
sudo update-initramfs -u
```
