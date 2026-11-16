---
date: 2026-11-15
status: accepted
---

# K8s 节点的系统与 k3s 由 nix-config 声明，本仓库不再有 Ansible

三台 k8s 节点运行 NixOS，系统、网络、k3s 参数、镜像源、审计策略与 Lima 实例配置都在 nix-config 的 `hosts/k8s/` 与 `modules/features/homelab/k3s-node/`。节点运维知识（重装流程、整集群关停顺序、获取 kubeconfig）写在 nix-config 的 `hosts/k8s/README.md`。home-ops 只管集群内的 GitOps，不再保存 `ansible/`，也不再提供 `task bootstrap`、`task cluster:*`、`task lima:*`。与 [ADR-0009](./0009-router-dnsmasq-declared-in-nix-config.md)、[ADR-0010](./0010-router-bird-avahi-declared-in-nix-config.md) 同一原则：一台机器的配置只有一个所有者

## Considered Options

- 继续用 Ansible 配置 Ubuntu：节点配置要在两个仓库维护，apt 包版本随时间漂移，重装后无法保证与原节点一致
- 保留 Ansible 或改写成脚本，只做整集群启停：没有必须保留的理由，关机顺序写成文档即可

## Consequences

- k3s 版本跟随 nix-config 的 nixpkgs，Renovate 不再跟踪；system-upgrade-controller 不适用于 NixOS
- 网卡命名由 NixOS 按 MAC 决定，取代 [ADR-0001](./0001-lima-network-ownership.md)
- 整集群启停没有脚本，按 nix-config 的 `hosts/k8s/README.md` 手动执行
- `scripts/check-registry-mirror-probes.py` 从 nix-config 的 `main` 分支读取 `registries.yaml`，校验镜像端点与 Gatus 探测清单一一对应；CI 需要能访问 GitHub
- GPU 节点的 vGPU 驱动与内核版本固定，版本与原因见 nix-config 的 `modules/features/homelab/k3s-nvidia-vgpu/README.md`
