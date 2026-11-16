# .taskfile

本目录是 home-ops 的 Task 子任务定义：把重复运维动作收成可调用的 `task <ns>:<name>`。

## 目录结构

- `.taskfile/`: 按领域拆分的 Taskfile（flux / kopia / k8s 等）
- `.taskfile/scripts/`: 被 task 调用的 shell（仅放多 task 共用或逻辑过重不宜内嵌的脚本）
- `Taskfile.yaml`（仓库根）: 入口，`includes` 挂载本目录各文件

## 基本约束

- **禁止硬编码**内网 IP、内网主机名、SSH `user@host`、节点名、VMID 等身份类参数；主机用 nix-config 生成的 ssh 别名，其余从已有定义读取，或运行时动态解析
- **已有定义优先**：对应 GitOps 声明（如 HelmRelease 的 LB IPAM）；本仓库不维护主机清单，不要另起一份平行清单
- **顶层 `sh:` 变量对整个 Taskfile 生效**（实测：同文件任意 task 运行都会执行它）。零成本的解析留顶层；`sops`、`yq` 这类昂贵或可能失败的解析放进真正需要它的 task，或放进 `internal: true` 的子任务让多个入口共用一份声明，否则无关动作也会被它拖住
- **共享抽取门槛**：同一取值在 **两处及以上** 被引用，才进入 `.taskfile/scripts/` 共享（如 `with-bws.sh`）；**只出现一次** 的留在当前 taskfile / 脚本本地，不预埋“以后可能用”的通用接口
- **最少代码**：先证明用更少代码能达到目的；能一行 kubectl/yq 解决的，不写多层封装；共享脚本保持小 CLI，避免 source 样板与未使用的子命令
- **幂等与安全**：启停类任务对已达目标状态应跳过（如服务已在运行）；破坏性步骤（强制 stop 之类）允许失败继续或有明确回退
- **互逆操作**：成对的 stop/start 必须按逆序成对实现；stop 多做的每一步，start 都要有对应恢复（如等服务 Ready）
- **对外暴露最小化**：`task --list` 只展示会直接执行的入口；仅被其他 task 组合调用的子步骤、纯调试/极少手跑的工具一律 `internal: true`（仍可被依赖调用，也可显式 `task ns:name` 跑）
- **集群外配置归 nix-config**：k8s 节点系统、路由器、旁路由、VPS 与 sakamoto 容器的声明和下发都在 nix-config，本目录不新增对应的下发 task
- **领域内聚**：同一领域的声明、模板、静态数据和专用脚本放在同一功能目录；远端配置优先落入同一专用目录，目标系统要求固定路径时除外

## 数据与分组（写 task 时）

- 主机：用 nix-config 生成的 ssh 别名；确实需要地址时用 `ssh -G <别名> | awk '/^hostname /{print $2}'`
- 这些主机的配置都由 nix-config 声明，本仓库的 task 只做连接与运维

## 新增 task 检查清单

- [ ] 有无硬编码 IP / 主机名 / 用户？能否改为 ssh 别名或声明式配置？
- [ ] 若抽了共享函数/脚本：调用方是否 ≥ 2？否则改回本地
- [ ] stop/start 是否互逆、是否对已是目标状态幂等？
- [ ] 是否用了最小实现，而不是提前抽象？
- [ ] 子步骤 / 调试 task 是否已 `internal: true`，`--list` 是否只剩入口？
