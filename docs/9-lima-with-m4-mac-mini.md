# Lima on Mac mini 虚拟机配置

Lima 实例配置由 nix-config 声明并生成（`system.build.limaYaml`），更新步骤见 nix-config 的 `hosts/k8s/README.md`，决策见 [ADR-0011](adr/0011-k8s-nodes-declared-in-nix-config.md)。以下是宿主机侧的准备与注意事项

## 桥接网络配置

桥接网卡走 Lima 的非托管模式：宿主用 launchd 常驻 `socket_vmnet`，Lima 实例配置里只写 socket 路径与固定 MAC。宿主不再手工编译 `socket_vmnet`，也不再安装 Lima 的 sudoers。准备、生效顺序与旧手工配置的清理见 nix-config 的「宿主的 socket_vmnet」小节：[`hosts/k8s/README.md`](https://github.com/shelken/nix-config/blob/main/hosts/k8s/README.md#宿主的-socket_vmnet)，原理见 [`modules/features/homelab/socket-vmnet/README.md`](https://github.com/shelken/nix-config/blob/main/modules/features/homelab/socket-vmnet/README.md)

固定 MAC 地址以确保 IP 稳定：节点内按 MAC 命名网卡，路由器按 MAC 做 DHCP 保留

## 数据盘配置

将 Lima 虚拟磁盘存储目录软链接至外置高速存储：

```bash
# 将lima的硬盘位置软链接到外置ssd
rm -rf ~/.lima/_disks
mkdir -p /Volumes/sakamoto-data/k8s/lima/_disks && ln -s /Volumes/sakamoto-data/k8s/lima/_disks ~/.lima/_disks

# 创建硬盘 默认ext4格式
limactl disk create longhorn --size 1024G
```

在配置里加上（`format: false` 不可省：Lima 会把脏盘当未初始化盘做 mkfs，覆盖 Longhorn 数据；被覆盖后的磁盘重新纳入见 [运维笔记的 Longhorn 小节](operations-notes.md#longhorn)）

```yaml
additionalDisks:
  - name: "longhorn"
    format: false
```

## 网络与磁盘变更注意

- 节点网络（接口命名、寻址、VLAN、DNS）由 nix-config 的 `hosts/k8s/common.nix` 声明，不在节点上手改
- 改完用 `ip -br a`、`ip route`、`networkctl status` 核对，`limactl list` 显示 Running 不代表 guest 网络就绪
- 用 `ip -d link` 区分接口名与 altname：`enp0s1` 可能只是 `eth0` 的 altname，看到 `renamed from` 不要直接判定接口改名
- 离线挂载 guest 磁盘前必须先停 VM，运行中挂载会造成 ext4 损坏
- 单控制面场景下，未定位根因不得重启宿主机，重启会打断取证并延长中断
