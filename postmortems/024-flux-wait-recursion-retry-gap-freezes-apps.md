# Flux 等待递归与重试间隙冻结 app 层

**日期**: 2026-09-28
**影响**: #1495 应用后 app 层 27 个应用 postBuild 失败 14 分钟（17:00:44 至 17:14:46），network 层 4 个网关子级连带阻塞
**发现人**: 用户

## 问题

内网域迁移（#1495）新增变量 `INTERNAL_DOMAIN`。revision 应用时，`network/certificates-import`、`certificates-export` 所在 namespace 的副本尚未写入该变量，两个子级以 strict 模式 postBuild 失败，且未声明 `retryInterval`，排定 1 小时后重试，依赖它们的 4 个网关子级因此卡在 InProgress。`infra`（`wait: true`）健康检查连续超时，`apps`（`dependsOn: infra`）14 分钟无法 reconcile，`default` 的 `cluster-secrets` 副本一直是旧值，27 个 app 子级每 2 分钟重试全部失败。

## 现象

```txt
certificates-export: variable substitution failed: variable not set (strict mode): "INTERNAL_DOMAIN" ... next try in 1h0m0s
infra: health check failed after 5m: timeout waiting for: [Kustomization/network/caddy-external status: 'InProgress', ...]
apps: Dependencies do not meet ready condition, retrying in 5s
icache: variable not set (strict mode): "INTERNAL_DOMAIN", next try in 2m0s
```

获取完整时间线（按 pod 全量拉取后本地过滤，管道过滤会被日志量淹没）：

```bash
curl -sG '<victoria-logs>/select/logsql/query' \
  --data-urlencode 'query={k_pod_name=~"kustomize-controller.*"}' \
  --data-urlencode 'start=<incident-start>+08:00' \
  --data-urlencode 'end=<incident-end>+08:00' -o ks-logs.jsonl
```

## 根因

- 变量产出方（namespace tree 由父级 Kustomization 应用）与消费方（子级 `substituteFrom`）之间无依赖，revision 触发时子级可能先于变量写入，本次竞态窗口 3 秒
- 未声明 `retryInterval` 的子级失败后按 `interval` 重试，本次 1 小时，3 秒竞态被放大成小时级等待
- `infra wait: true` 令父级 Ready 递归包含全部孙级健康，`apps dependsOn: infra` 把两个对象的局部失败放大为整层冻结，该 `wait: true` 仅为 2025-10-25 集群重建期的顺序需求（`847f1db3`）

## 修复

- 8 个未声明 `retryInterval` 的对象补 `retryInterval: 2m`（certificates-import/export、mosquitto、cloudflare-tunnel、tailscale/tailscale-proxy、fluent-bit、victoria-logs，#1501），未用父级 patch 统一覆盖，避免改写本就正确的子级并隐藏归属
- `infra.wait: false`（#1501），顺序仍由 `apps.dependsOn: infra` 保证
- 新增巡检 `scripts/verify-ks-retry-interval.sh`（#1501）
- 同批迁移的消费者遗漏：gatus 配置由进程内 `${VAR}` 展开，未注入 `INTERNAL_DOMAIN`，探针请求 `https://minio./`（#1502）

## 预防

- 子级 Kustomization 变更后执行 `bash scripts/verify-ks-retry-interval.sh`
- 新增 postBuild 变量时核对消费方替换机制：Flux `substituteFrom`、进程内展开（标注 `substitution.flux/disabled` 的资源须补 Deployment env）、kustomize 层
- 需要顺序时用子级 `dependsOn`，父级不加 `wait: true`
- 停滞排查：`flux get ks -A` 找 blocked 父级，kustomize-controller 日志看原因，再看失败子级的 `next try in`

## 诊断误区

- 冻结时长误报 47 分钟 → 用首末失败样本的时间戳核对
- 把缺少 `retryInterval` 的对象整体当元凶 → 只有 certificates-import/export 真正失败，其余为依赖连坐
- minio 探针先怀疑 DNS 链路 → 实为环境变量未注入，`hide-hostname: true` 掩盖了真实 URL
- 靠 `git log -S` 推断 `apps.dependsOn` 动机 → 提交信息只有「fix」，需结合当时集群状态判断
