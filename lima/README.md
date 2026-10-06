# Lima VM 配置

本目录是 Lima 实例声明，通过 `.taskfile/lima.yaml` 的 `task lima:*` 下发到宿主机

- `sakamoto.yaml`: sakamoto 宿主机上的 k3s 控制面节点 VM，带 Longhorn 附加盘
- `yuuko.yaml`: yuuko 宿主机上的 k3s 工作节点 VM
- `recovery.yaml`: 单次恢复群晖磁盘数据的临时 VM，块设备直通，需 Lima v2.2.0-dev 以上

VM 生命周期操作复用已有 `lima:*` task，写 task 前读 [.taskfile/AGENTS.md](../.taskfile/AGENTS.md)
