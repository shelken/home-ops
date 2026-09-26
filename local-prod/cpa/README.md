# cli-proxy-api 本地离线运行

把集群里的 cpa 迁到 Mac 本地 Docker 运行，外出无集群时继续用；回家把本地运行期间轮转的 token 写回集群。术语见 [../CONTEXT.md](../CONTEXT.md)。

## 功能

- `task checkout`：停集群端 → PVC 数据(约 61M)镜像到本地 → 本地接管
- `task checkin`：本地停 → 备份远端现状 → 写回 → 恢复集群
- `task status`：只读查看两侧状态
- `task local-up` / `local-down`：单独控制本地容器

## 快速上手

```bash
# 出发前(在集群网络内)
task -d local-prod/cpa checkout        # 完成后所有权 = LOCAL, 集群 cpa 已停

# 外出期间
# omp 客户端端点手动切到 http://localhost:8317 (nix-config 里改)

# 回家后
task -d local-prod/cpa checkin         # 完成后所有权 = REMOTE, 集群 cpa 已恢复
# omp 客户端端点切回集群入口
```

## 边界与约定

| 事项 | 约定 |
|---|---|
| 单写入端 | 任何时刻只有集群或本地一侧在写 token, 由 `.state` + 前置检查强制 |
| Gatus | 外出期间外部探测会持续 503 告警, 已知并接受 |
| 回滚 | checkin 写回前远端现状自动备份到 `backup/<时间戳>/`; 集群侧另有 kopiur(VolSync/Kopia) 定期备份 |
| 中断恢复 | checkout 失败: 重跑 `checkout` 即可(前置只挡重复 LOCAL); checkin 失败: 本地 `data/` 与 `backup/` 均完好, 重跑 `checkin` |
| 端口 | 本地 8317(api) + 8085/1455/51121(各上游登录回调), 均只绑 127.0.0.1 |
| 插件 | 60M plugins 随 PVC 一起带走, 离线可用 |

## 文件说明

- `data/` `config/` `backup/` `.state` 均已 gitignore, 不进 git
- `data/auths/` 是集群里挂到 `/root/.cli-proxy-api` 的历史遗留子目录(cpa 实际用 `data/for-run/`), 随镜像写回, 不挂载进本地容器
- `config/config.yaml` 每次 checkout 从集群 secret 重新拉取, 含 provider keys, 不要提交
