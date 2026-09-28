# Flux wait 递归 + 重试间隙冻结 app 层

**日期**: 2026-09-28
**影响**: #1495（内网域迁移）应用后，app 层 27 个应用 postBuild 全部失败约 14 分钟（17:00:44–17:14:46）；期间 network 层 4 个网关子级连带阻塞，人工介入后才收敛
**发现人**: 用户

## 问题

内网域迁移（#1495）新增变量 `INTERNAL_DOMAIN` 并改造大量消费者。新 revision 应用瞬间：

1. `network/certificates-export`、`certificates-import` 两个子级以 strict 模式 postBuild 失败（其 namespace 的 `cluster-secrets` 副本尚未写入新变量），且它们未声明 `retryInterval`，失败后按 `interval` 排定 **1 小时后** 重试
2. 两个对象 Ready=False → 依赖它们（直接或间接）的 `caddy-external`、`envoy-gateway`、`gateway-policy`、`gateway-filter` 卡在 InProgress
3. `infra` 层 `wait: true`，其 Ready 递归要求上述孙级健康 → health check 连续 5 分钟超时
4. `apps` 层 `dependsOn: infra` → 14 分钟无法 reconcile → `default` 里唯一的 `cluster-secrets` 副本一直是旧值
5. 27 个 app 子级每 2 分钟重试，但变量永远等不到 → 全部失败

## 现象

```txt
# 17:00:44 变量尚未落到 network namespace，子级抢跑
certificates-export error: post build failed for 'Certificate.v1.cert-manager.io/ooooo-space-tls':
  envsubst error: variable substitution failed: variable not set (strict mode): "INTERNAL_DOMAIN"
  ... next try in 1h0m0s

# 17:05:47 / 17:10:49 infra 递归健康门禁超时
infra error: health check failed after 5m0.01s: timeout waiting for:
  [Kustomization/network/caddy-external status: 'InProgress', ... certificates-import InProgress]

# 17:00:45–17:14:46 apps 每 5 秒探测依赖（约 170 次）
apps info: Dependencies do not meet ready condition, retrying in 5s

# 17:08–17:14 app 子级反复失败（变量永远不来）
icache error: variable not set (strict mode): "INTERNAL_DOMAIN", next try in 2m0s
```

复现查询（VictoriaLogs，按 pod 全量拉取后本地过滤，避免管道过滤被日志量淹没）：

```bash
curl -sG '<victoria-logs>/select/logsql/query' \
  --data-urlencode 'query={k_pod_name=~"kustomize-controller.*"}' \
  --data-urlencode 'start=2026-09-28T16:30:00+08:00' \
  --data-urlencode 'end=2026-09-28T18:30:00+08:00' -o /tmp/ks.jsonl
```

## 根因

1. **变量供需之间没有依赖，只有时序巧合**：`cluster-secrets` 由 namespace tree（⇒ 父级 Kustomization）应用，消费它的子级只声明 `substituteFrom`，不依赖产出者。revision 变更同时触发全部子级 reconcile，子级必然可能先失败（本次竞态窗口 3 秒）。
2. **失败重试周期退化为 interval**：未声明 `retryInterval` 的对象失败后按 `interval` 重试，本次为 1h。3 秒竞态被放大成小时级等待。
3. **层 Ready 递归放大**：`infra wait: true` 使 infra 的 Ready 包含全部孙级健康，`apps dependsOn: infra` 于是把 network 层两个对象的局部失败放大为整个 app 层冻结。该 `wait: true` 的动机只是 2025-10-25 集群重建期（`847f1db3`）的一次性顺序需求，稳态下无收益。

## 修复

1. 8 个未声明 `retryInterval` 的对象（certificates-import/export、mosquitto、cloudflare-tunnel、tailscale/tailscale-proxy、fluent-bit、victoria-logs）就地补 `retryInterval: 2m`（#1501）。不用父级 blanket patch——那会覆盖本就正确的 91 个子级并藏掉归属。
2. `infra.wait: true → false`（#1501）：`dependsOn` 语义保留（apps 仍在 infra apply 之后 reconcile），但不再继承孙级健康。
3. 新增巡检 `scripts/verify-ks-retry-interval.sh`（#1501）：遍历 `k8s/**/ks.yaml`，缺 `retryInterval` 即 exit 1。
4. 同一迁移暴露的另一个消费者遗漏：gatus 的 ConfigMap 标注了 `kustomize.toolkit.fluxcd.io/substitute: disabled`，`${VAR}` 由 gatus 进程用环境变量展开，但 `INTERNAL_DOMAIN` 未注入 → URL 变成 `https://minio./...`，探针每分钟 NXDOMAIN（#1502）。

## 预防

- 新增/修改子级 Kustomization 后执行 `bash scripts/verify-ks-retry-interval.sh`，任何缺 `retryInterval` 的文件都会失败。
- 新增 postBuild 变量时逐一核对消费方替换机制：Flux `postBuild.substituteFrom`、进程内展开（gatus 等 `substitute: disabled` 资源，必须同时补 Deployment env）、kustomize 层替换。
- 需要部署顺序时用子级 `dependsOn` 表达；**不要**用父级 `wait: true` 换顺序——它会引入递归健康门禁，把局部故障放大为整层冻结。
- 排查 Flux 停滞三步：`flux get ks -A` 找出 blocked 的父级 → 查 kustomize-controller 日志确认 blocked 原因（`Dependencies do not meet ready condition` / `health check failed`）→ 再看真正失败的子级及其**排定重试时间**（`next try in ...`）。

## 诊断误区（本次实际踩过）

- 把 app 层冻结时长报成 47 分钟（实际 14 分钟，17:00:44→17:14:46），并误判解锁点是后续的 #1500 合并。
- 把"缺 `retryInterval` 的 6 个对象"整体当成元凶；实际只有 certificates-import/export 失败，另外 4 个 network 子级是依赖连坐，fluent-bit/victoria-logs/mosquitto 等从未失败。
- 在 minio 探针问题上先怀疑 DNS 链路（查了 CoreDNS 两副本、三个节点、pod 内解析），实际是环境变量未注入；`hide-hostname: true` 掩盖了真实 URL，UI 只显示 lookup 失败。
- 曾依据 `git log -S` 判断 `apps.dependsOn` 的引入动机，结论需与当时的集群状态对照验证——单看提交信息（"fix"）无法还原意图。
