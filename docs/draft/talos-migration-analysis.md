# Talos 迁移分析：从 k3s 到 Talos Linux

> **状态**: 草稿 - 待决策
> **创建日期**: 2025-12
> **参考**: [onedr0p/home-ops](https://github.com/onedr0p/home-ops)

## 目录

- [一、背景与动机](#一背景与动机)
- [二、onedr0p 的 Talos 配置分析](#二onedr0p-的-talos-配置分析)
- [三、当前设备兼容性分析](#三当前设备兼容性分析)
- [四、Lima vs QEMU 性能分析](#四lima-vs-qemu-性能分析)
- [五、迁移方案](#五迁移方案)
- [六、决策点](#六决策点)

---

## 一、背景与动机

### 为什么考虑 Talos？

| 特性 | k3s (当前) | Talos |
|------|------------|-------|
| 操作系统 | 通用 Linux (Ubuntu) | 不可变、专用 Kubernetes OS |
| 配置管理 | Ansible + cloud-init | 声明式 API (talosctl) |
| 安全性 | 依赖 OS 配置 | 最小化攻击面，无 SSH |
| 升级 | 手动或 system-upgrade-controller | 原子升级，A/B 分区 |
| 调试 | SSH 登录 | talosctl API |

### onedr0p 的选择理由

- 使用 3 台 ASUS NUC 物理机运行 Talos
- 全 amd64 架构，硬件统一
- 使用 Rook-Ceph
- 使用 1Password 管理敏感配置

---

## 二、onedr0p 的 Talos 配置分析

### 配置结构

```
talos/
├── machineconfig.yaml.j2     # 主机器配置模板
├── schematic.yaml.j2          # 系统扩展定义
├── mod.just                    # Just 任务文件
└── nodes/                      # 节点特定配置
    ├── k8s-0.yaml.j2
    ├── k8s-1.yaml.j2
    └── k8s-2.yaml.j2
```

### 核心配置特点

1. **Jinja2 模板化**: 使用 minijinja 渲染配置
2. **1Password 集成**: 密钥通过 `op://kubernetes/talos/*` 引用
3. **网络配置**:
   - Bond 网络 (active-backup)
   - Thunderbolt 直连网络
   - VLAN 隔离 (IoT, VPN)
4. **存储**: Rook-Ceph (非 Longhorn)
5. **CNI**: Cilium (禁用 kube-proxy, CoreDNS)

### machineconfig.yaml.j2 关键配置

```yaml
machine:
  features:
    hostDNS:
      enabled: true
      forwardKubeDNSToHost: true  # Cilium 需要
    kubePrism:
      enabled: true
      port: 7445

  kubelet:
    nodeIP:
      validSubnets:
        - 192.168.42.0/24

  sysctls:
    fs.inotify.max_user_instances: "8192"
    fs.inotify.max_user_watches: "1048576"
    net.ipv4.tcp_congestion_control: bbr

cluster:
  network:
    cni:
      name: none  # 使用 Cilium
  coreDNS:
    disabled: true
  proxy:
    disabled: true
```

---

## 三、当前设备兼容性分析

### 节点概览

| 节点 | 当前环境 | Talos 兼容性 | 难度 | 建议 |
|------|----------|--------------|------|------|
| **sakamoto-k8s** | Lima VM (Mac M4, vz) | ⚠️ 需改用 QEMU | 中等 | 见性能分析 |
| **homelab-1** | Proxmox VM (amd64) | ✅ 完全支持 | 简单 | 推荐先迁移 |
| **tvbox** | Armbian (S905x3) | ❌ 不支持 | N/A | 保留 k3s 或移除 |
| **yuuko-k8s** | Lima VM (Mac M1, vz) | ⚠️ 需改用 QEMU | 中等 | 见性能分析 |

### 问题详解

#### 1. Lima VM 不适合 Talos

Lima 是为 macOS 设计的轻量级 Linux VM 方案：
- 使用 cloud-init 配置，Talos 不支持
- Lima 的 `vz` 模式使用 Virtualization.framework，性能最佳
- Talos 官方只支持 QEMU provisioner

**替代方案**:
- `talosctl cluster create --provisioner=qemu` (使用 HVF 硬件加速)
- UTM (QEMU 图形化前端)

#### 2. ARM 电视盒子 (tvbox) 不支持

- Talos 对 ARM SBC 支持有限 (仅 RPi4/5, Jetson 等)
- Amlogic S905x3 无官方支持
- 无法自行编译支持

#### 3. Longhorn vs Rook-Ceph

| 存储方案 | 当前使用 | onedr0p | Talos 支持 |
|----------|----------|---------|------------|
| Longhorn | ✅ | ❌ | ✅ (需额外配置) |
| Rook-Ceph | ❌ | ✅ | ✅ (推荐) |
| OpenEBS | 部分 | ❌ | ✅ |

---

## 四、Lima vs QEMU 性能分析

### 虚拟化架构对比

| 层级 | Lima + VZ (当前) | QEMU + HVF (Talos) |
|------|------------------|---------------------|
| **虚拟化框架** | Virtualization.framework | Hypervisor.framework |
| **设备模拟** | Apple 原生 VirtIO | QEMU 模拟层 |
| **磁盘 I/O** | 原生 VirtIO-blk | QEMU VirtIO-blk |
| **网络** | vmnet.framework | vmnet (via QEMU) |
| **CPU 虚拟化** | 直接 ARM64 虚拟化 | HVF 硬件加速 |

### 架构示意图

```
Lima + VZ:
┌─────────────────────────────────┐
│       Guest OS (Ubuntu)         │
├─────────────────────────────────┤
│   Virtualization.framework      │  ← Apple 原生，最小开销
├─────────────────────────────────┤
│       macOS Kernel              │
└─────────────────────────────────┘

QEMU + HVF:
┌─────────────────────────────────┐
│       Guest OS (Talos)          │
├─────────────────────────────────┤
│         QEMU 模拟层              │  ← 额外开销在这里
├─────────────────────────────────┤
│    Hypervisor.framework (HVF)   │  ← 硬件加速
├─────────────────────────────────┤
│       macOS Kernel              │
└─────────────────────────────────┘
```

### 性能损失估算

#### CPU 性能

| 场景 | Lima + VZ | QEMU + HVF | 损失 |
|------|-----------|------------|------|
| 纯计算任务 | ~95-98% | ~90-95% | **3-5%** |
| 系统调用密集 | ~90-95% | ~85-90% | **5-10%** |

#### 磁盘 I/O 性能 (差异最大)

| 场景 | Lima + VZ | QEMU + HVF | 损失 |
|------|-----------|------------|------|
| 顺序读写 | ~85-90% | ~70-80% | **10-15%** |
| 随机 IOPS | ~80-85% | ~60-70% | **15-25%** |
| 小文件操作 | ~75-80% | ~55-65% | **15-25%** |

#### 网络 I/O 性能

| 场景 | Lima + VZ | QEMU + HVF | 损失 |
|------|-----------|------------|------|
| 吞吐量 | ~90% | ~80-85% | **5-10%** |
| 延迟 | 低 | 略高 | **5-15%** |

### 综合性能评估

以 Lima+VZ 为 100 分基准：

| 方案 | 综合性能 | 说明 |
|------|----------|------|
| Lima + VZ (当前) | **100** | 基准 |
| QEMU + HVF (Talos) | **85-90** | 损失约 10-15% |
| QEMU 无硬件加速 | **15-25** | 不可接受 |

### 对 Kubernetes 组件的影响

| 组件 | 影响程度 | 说明 |
|------|----------|------|
| etcd | ⚠️ 中等 | 磁盘 I/O 密集，可能感受到 10-15% 下降 |
| kube-apiserver | 🟢 低 | 主要是内存和 CPU 操作 |
| Longhorn | ⚠️ 中等 | 存储复制依赖磁盘和网络 I/O |
| Cilium | 🟡 低-中 | eBPF 性能可能略受影响 |

---

## 五、迁移方案

### 方案 A: 仅迁移 Proxmox 节点 (推荐起步)

**目标**:
- `homelab-1` (PVE) → Talos (control-plane 或 worker)
- 其他节点保持现状

**步骤**:

1. 下载 Talos ISO (AMD64)
```bash
wget https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.11.6/metal-amd64.iso
```

2. 在 Proxmox 创建 VM
   - BIOS: OVMF (UEFI)
   - Machine: q35
   - CPU: host, 4+ cores
   - Memory: 14GB (禁用 ballooning)
   - Disk: **VirtIO SCSI** (非 VirtIO SCSI Single!)
   - Network: virtio

3. 生成并应用配置
```bash
talosctl gen config my-cluster https://192.168.6.110:6443 --output-dir _out
talosctl apply-config --insecure --nodes 192.168.6.110 --file _out/controlplane.yaml
talosctl bootstrap --nodes 192.168.6.110
```

### 方案 B: Mac Mini 改用 QEMU

**前提**: 接受 10-15% 性能损失

1. 停止并删除 Lima VM
```bash
limactl stop sakamoto-k8s
limactl delete sakamoto-k8s
```

2. 使用 talosctl 创建 QEMU 集群
```bash
brew install qemu siderolabs/tap/talosctl

# 下载 Talos kernel/initramfs (ARM64)
mkdir -p _out
curl -L https://github.com/siderolabs/talos/releases/download/v1.11.6/vmlinuz-arm64 -o _out/vmlinuz-arm64
curl -L https://github.com/siderolabs/talos/releases/download/v1.11.6/initramfs-arm64.xz -o _out/initramfs-arm64.xz

# 创建集群
mkdir -p ~/.talos/clusters
talosctl cluster create \
  --provisioner=qemu \
  --arch=arm64 \
  --controlplanes=1 \
  --workers=0 \
  --cpus=6 \
  --memory=14336
```

### 方案 C: 混合架构 (不推荐)

Talos 和 k3s 不能混合在同一集群中，只能运行两个独立集群。

---

## 六、决策点

### 需要回答的问题

1. **性能 vs 特性**: 是否愿意接受 10-15% 性能损失换取 Talos 的不可变/安全特性？

2. **tvbox 的去留**:
   - 移除出集群？
   - 保留运行独立 k3s？
   - 迁移轻量工作负载到其他节点？

3. **存储方案**:

回答：使用longhorn，Rook-Ceph需要资源更多

4. **迁移范围**:
   - 仅 Proxmox 节点？
   - 全部迁移？
   - 分阶段迁移？

### 待完成事项

- [ ] 在 Proxmox 上测试 Talos 单节点
- [ ] 验证 Cilium 配置兼容性
- [ ] 验证 Longhorn 在 Talos 上的配置
- [ ] 评估 QEMU 在 Mac Mini 上的实际性能
- [ ] 决定 tvbox 的处理方式

---

## 参考资源

- [Talos 官方文档](https://www.talos.dev/v1.11/)
- [onedr0p/home-ops Talos 配置](https://github.com/onedr0p/home-ops/tree/main/talos)
- [Talos Proxmox 安装指南](https://www.talos.dev/v1.11/talos-guides/install/virtualized-platforms/proxmox/)
- [Talos QEMU 安装指南](https://www.talos.dev/v1.11/talos-guides/install/local-platforms/qemu/)
- [Lima 虚拟化类型](https://lima-vm.io/docs/config/vmtype/)
