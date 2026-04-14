# 检查点

## 1. 已完成上下文检查
- 状态: 已完成
- 结论: 已确认告警通过 Alertmanager webhook 触发 `restart-passwall.sh`，现有 `groupWait` 为 30s，脚本内需要自行兜底 90s 冷却；相关尸检强调重启前必须清理 `/tmp/lock/passwall_monitor.lock`。

## 2. 调整 passwall 重启触发脚本
- 状态: 已完成
- 结论: LuCI 执行改为后台触发 `passwall restart` 并写日志到 `/tmp/passwall-healer-restart.log`，HTTP 请求超时降为 15s；新增 `/tmp/passwall-restart.last` 冷却文件，重触发间隔要求大于 90s。

## 3. 执行验证
- 状态: 已完成
- 结论: 已通过 `sh -n k8s/infra/common/network/internal/passwall-healer/app/resources/restart-passwall.sh` 和 `pre-commit run --files k8s/infra/common/network/internal/passwall-healer/app/resources/restart-passwall.sh PLAN.md`。

# 实现步骤

1. 检查现有脚本、告警触发配置、既往尸检，确认冷却约束落点。
2. 修改 `restart-passwall.sh`，让重启请求快速返回，并在脚本内强制 90s 以上冷却。
3. 运行针对性验证，确认脚本语法和配置一致性。
