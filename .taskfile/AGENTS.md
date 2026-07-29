# .taskfile

本目录是 home-ops 的 Task 子任务定义：把重复运维动作收成可调用的 `task <ns>:<name>`。

## 目录结构

- `.taskfile/`: 按领域拆分的 Taskfile（compose / lima / cluster / k8s 等）
- `.taskfile/scripts/`: 被 task 调用的 shell（仅放多 task 共用或逻辑过重不宜内嵌的脚本）
- `Taskfile.yaml`（仓库根）: 入口，`includes` 挂载本目录各文件

## 基本约束

- **禁止硬编码**内网 IP、内网主机名、SSH `user@host`、节点名、VMID 等身份类参数；必须从已有定义读取，或运行时动态解析
- **已有定义优先**：`ansible/inventory/`（`hosts.ini` / `others.ini` 分组）、对应 GitOps 声明（如 HelmRelease 的 LB IPAM）；不要另起一份平行清单
- **共享抽取门槛**：同一取值在 **两处及以上** 被引用，才进入 `.taskfile/scripts/` 共享（如 `inv.sh`）；**只出现一次** 的留在当前 taskfile / 脚本本地，不预埋“以后可能用”的通用接口
- **最少代码**：先证明用更少代码能达到目的；能一行 inventory/kubectl/yq 解决的，不写多层封装；共享脚本保持小 CLI，避免 source 样板与未使用的子命令
- **幂等与安全**：启停类任务对已达目标状态应跳过（如 VM 已 stopped/running）；破坏性步骤（drain、强制 stop）允许失败继续或有明确回退，不把「全库存 hosts: all」式假设带进运维脚本的数据源选择
- **互逆操作**：成对的 stop/start 必须按逆序成对实现；stop 多做的每一步，start 都要有对应恢复（如等 API / nodes Ready）
- **整集群下电 ≠ 撤节点**：不 drain/cordon（会撞 Longhorn/CNPG 等 PDB）。drain 只用于「集群继续跑、只撤一台」
- **集群启停走 Ansible**：`playbooks/cluster-stop.yml` / `cluster-start.yml`（unit 名 `k3s.service`，与 xanmanning.k3s 一致）；`task cluster:*` 只做薄封装。库存需同时 `-i hosts.ini -i others.ini`
- **对外暴露最小化**：`task --list` 只展示会直接执行的入口；仅被其他 task 组合调用的子步骤、纯调试/极少手跑的工具一律 `internal: true`（仍可被依赖调用，也可显式 `task ns:name` 跑）。示例：`cluster` 只暴露 start/stop/status

## 数据与分组（写 task 时）

- k8s 节点：`ansible/inventory/hosts.ini` 的 `controllers` / `workers`
- 集群外主机：`ansible/inventory/others.ini`；注意分组语义——`vps` 可 bootstrap，`endpoint` / `router` / `hypervisor` 仅连接与运维，不要把「枚举用并集」当成可批量配置的目标集
- control-plane 虚拟机生命周期：复用已有 `lima:*`，不要在 cluster 里重写一份 Lima 操作
- worker 虚拟机：PVE 侧按 guest IP 与 cloud-init `ipconfig` 反查 VMID，不写死 VMID

## 新增 task 检查清单

- [ ] 有无硬编码 IP / 主机名 / 用户？能否改为 inventory 或声明式配置？
- [ ] 若抽了共享函数/脚本：调用方是否 ≥ 2？否则改回本地
- [ ] stop/start 是否互逆、是否对已是目标状态幂等？
- [ ] 是否用了最小实现，而不是提前抽象？
- [ ] 子步骤 / 调试 task 是否已 `internal: true`，`--list` 是否只剩入口？
