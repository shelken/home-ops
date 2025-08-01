# GPU

> 以下都是在PVE上的显卡相关操作

## NVIDIA

### vGPU

> TODO

### VM 显卡直通

> 笔记本架构的GPU直通还是有问题。一直 no device found. 即使驱动看起来都正常
>
> 在系统2410, 2404，。各种版本535 550 570 都试过，没用。跟romfile或者NVIDIA的限制可能有关

UEFI情况下，VM关闭「安全启动」

然后进入安装

```shell
sudo apt install nvidia-headless-570-server
sudo reboot
```

安装driver后VM中检查：

```shell
lsmod | grep nvid
lspci -nnk | grep -A5 NVI
# ffmpeg
ffmpeg -decoders | grep cuvid
```
https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#with-apt-ubuntu-debian
[k3s中配置nvidia-container-toolkit](https://docs.k3s.io/advanced#nvidia-container-runtime)

```shell
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

```shell
./NVIDIA-Linux-x86_64-535.247.01.run --no-kernel-module
```

### 分配

```shell
k label node [node] nvidia.com/gpu.present=true
```

## INTEL

### 添加gpu到vm

在完成pve直通intel gpu的一些操作之后，给vm添加pci

```shell
# 然后确保存在 renderD128
ls -la /dev/dri

# ubuntu cloudimage缺少相关i915的加载 需要安装
sudo apt install linux-modules-extra-$(uname -r)
sudo apt install linux-firmware
```

检查

```shell
lspci -nnk | grep -B5 i915
```

### 分配

```shell
k label node [node] intel.feature.node.kubernetes.io/gpu=true
```