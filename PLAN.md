# Checkpoints

## 1. 定位 Renovate 自动合并规则
- [x] 已确认 `cli-proxy-api` 自动合并来自 `.renovate/automerge.json5`
- [x] 已确认当前目标是移除该服务的自动合并白名单
- [x] 已确认现有开放 PR：`#1090`

## 2. 调整配置
- [x] 从 `.renovate/automerge.json5` 的 docker 自动合并规则里移除 `eceasy/cli-proxy-api`
- [x] 保持其它镜像自动合并规则不变

## 3. 验证与审阅
- [x] 已用 `git diff --check -- .renovate/automerge.json5 PLAN.md` 确认无空白与格式问题
- [x] 已用 Node 求值 `.renovate/automerge.json5`，确认 JSON5 语法有效，docker 自动合并规则现仅保留 `kube-prometheus-stack`、`api-gateway`、`grafana`
- [x] 已完成独立审阅，确认本次 diff 只移除 `cli-proxy-api` 自动合并匹配项，未影响其它规则
- [x] 提交并推送

# Plan

1. 仅修改 `.renovate/automerge.json5`，移除 `cli-proxy-api` 自动合并匹配项。
2. 运行校验，确认 diff 只包含目标改动与本次 `PLAN.md`。
3. 使用独立审阅代理检查规则影响范围。
4. 提交并推送到 `main`。
