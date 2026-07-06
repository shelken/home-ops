---
name: k8s-incident-analysis
description: Kubernetes 事故取证流程。Use when 服务离线但没告警、升级后异常、K8s 应用/入口/备份链路失败、Gatus/Prometheus/Alertmanager 异常、Envoy Gateway 403/GeoIP/RBAC 异常、audit log 追溯手动操作、router-dns-proxy 延迟/失败、外部访问抖动，或需要统一时间线定位故障断点。
---

# K8s Incident Analysis

目标：用同一套取证流程，把故障断点定位到应用、入口、探测、采集、规则、路由、通知、集群外网络，或人工变更。

## Quick start

先读 [REFERENCE.md](REFERENCE.md) 的命令模板；涉及家宽出口、代理 DNS 或路由器时，运行 `scripts/router-network-snapshot.sh` 收集现场。

1. **定窗**：定义故障窗口，统一到 UTC；记录用户观察、自动恢复、人工干预、恢复时间。完成标准：每条关键证据都有时间戳和时区。
2. **证据锁**：先取证再修复。删除/重启 Pod、rollout、reconcile、patch 前，先保存聚合日志、当前 Pod 状态、必要的 config_dump/stats。完成标准：恢复动作不会抹掉唯一现场。
3. **查变更**：对齐 GitOps 期望、集群当前状态、最近提交/PR/Release。完成标准：能说明“本地工作区、Git、集群”三者是否一致。
4. **查历史**：历史日志优先 Victoria Logs；`kubectl logs` 只补当前/previous 容器细节。完成标准：跨 Pod/跨时间窗统计来自持久日志，而不是只看当前 Pod。
5. **跑六段**：探测 → 采集 → 规则 → 路由 → 通知 → 外部网络旁路。完成标准：断点落在一个明确段，且能说明为什么不是其它段。
6. **写发现**：如果仓库有 `docs/DISCOVERY.md`，每个新事实先查是否已记录；没有就追加。完成标准：重要证据不只留在对话里。
7. **给结论**：输出时间线、断点、排除项、下一步；需要变更时只给 GitOps/声明式方案，不执行 `kubectl apply`。

## Workflows

### 1) 建立时间线

- 区分“业务故障”和“监控平面故障”。
- 把自动恢复、手动操作、控制器重建、Pod SIGTERM、镜像/配置更新放进同一条 UTC 时间线。
- 不把“重启后没复现”说成“重启证明根因”；先看故障是否本来就是间歇性的。

### 2) 最近变更排查

- 对齐三件事：GitOps 期望版本、集群当前运行镜像/配置、故障窗口前后的提交/PR/release。
- 服务刚升级时，先查上游 release、merged/open PR、精确错误关键词。
- 回退不是默认动作；必须先用日志、PR diff/release note、版本差异证明当前错误与升级相关。

### 3) 六段排查

1. **探测段**：Gatus / blackbox / sidecar 是否持续失败。
2. **采集段**：Prometheus 是否真的抓到了对应时序。
3. **规则段**：规则是否 loaded、health 是否正常、是否满足 `for`。
4. **路由段**：Alertmanager 是否命中正确 receiver。
5. **通知段**：接收端是否真的收到/处理 webhook。
6. **外部网络旁路**：路由器、代理 DNS、WAN/WWAN、上游 DNS / 无线中继是否抖动。

### 4) Envoy Gateway 403 / GeoIP / RBAC 分支

触发：Gatus external 403、Envoy access log 出现 `rbac_access_denied_matched_policy[DENY]`、GeoIP 规则异常、XFF/client IP 相关异常。

- 先用 Victoria Logs 拉完整窗口，按 Pod、Pod IP、Host、status、`response_code_details`、`x-forwarded-for` 聚合；不要只看当前 Envoy Pod。
- 如果需要删除/重启 Envoy Pod，先抓：access log 时间窗、Pod startTime、SIGTERM 前后日志、config_dump、`/stats/prometheus`、相关 SecurityPolicy/ClientTrafficPolicy/EnvoyProxy live YAML。
- 校验 XFF 取址模型：`ClientTrafficPolicy.clientIPDetection`、trusted hops、Gatus 是否走公网入口、是否手动塞了不等价的第二跳。
- 区分三类问题：DB 文件内容错、DB 更新模型错、Envoy 运行时 GeoIP/RBAC 状态错。
- 对 node-local hostPath 数据，检查 updater 是否每节点更新、是否原子替换、是否有重复/漂移的旧 Job/CronJob。
- 原生 `SecurityPolicy` 不能表达 header absent/not-present；不要把“私网 CIDR 放行”写成旧 RBAC unknown 放行的等价实现。

完成标准：能说明 403 是哪个策略/过滤器返回、哪些 Pod 受影响、故障起点是否对齐配置/DB 更新/Pod 重建，并保留重启前现场。

### 5) Gatus / Prometheus / Alertmanager 规则

- Gatus 无 storage 时，API 只代表本次启动以来窗口；先记录 window_start/window_end。
- `Prometheus 没有时序` 不等于 `故障没发生`；先排除抓取缺口、Pod 重建、监控盲区。
- `Alertmanager 有发送成功` 不等于 `最终动作生效`；必须对照接收端日志。
- DNS 检测里，区分真实解析超时和 `[RESPONSE_TIME]` 成功阈值过紧。

### 6) Audit log / 手动操作追溯分支

触发：用户问“谁 apply/patch/delete 了什么”、集群有 GitOps 漂移、需要查手动操作残留。

- 同时读取当前 `audit.log` 和轮转文件；Kubernetes 轮转文件可能是 `audit-<timestamp>.log`，不要只查 `audit.log*`。
- 先确认可见窗口：最早/最晚 event、`--audit-log-maxsize`、`--audit-log-maxbackup`、目录中实际文件数。
- `Metadata` 级别没有 request body；“apply”只能用 `verb=patch`、`fieldManager=kubectl/kubectl-client-side-apply`、`dryRun=All` 近似判定。
- 查 live 残留时，用 `kubectl.kubernetes.io/last-applied-configuration` 找当前对象，但这只能说明对象曾被 apply，不等于 24 小时内 apply。
- 统计噪声时按 user、userAgent、verb、resource 排名；controller 高频写操作通常来自 Events、SAR/TokenReview、Longhorn/Flux/KEDA/VolSync 等。

完成标准：明确 audit 可见窗口、人工 kubectl 写操作数量、疑似 apply 对象、当前残留对象，以及哪些事件因轮转已不可查。

### 7) 集群外网络旁路

涉及外部 API 超时、`router-dns-proxy`、家宽出口、代理 DNS、Wi‑Fi 中继时，补这条旁路线。

- 普通公网 RTT 正常，不代表代理 DNS 正常；DNS、代理、出口要拆开测。
- `53` 正常、`15355` 正常，不代表 `15353` 正常。
- 集群内 HTTP/ICMP 正常，但外部域名/DNS 慢时，优先查路由器、代理 DNS、上游 DNS、WAN/WWAN。

## Output format

结论必须包含：

- 3~8 个关键时间点。
- 断点位置：应用/入口/探测/采集/规则/路由/通知/外部网络/人工变更。
- 最近变更判断：有无关联、是否建议 GitOps 回退或声明式修复。
- 证据命令与关键输出。
- “为什么不是其它段”的排除依据。
- 已更新或需要更新的 `docs/DISCOVERY.md` / postmortem 记录。
- 如涉及路由器/出口，单独说明是基础出网、DNS、代理 DNS 还是无线链路问题。

## Advanced

按需使用 `scripts/gatus-runtime-snapshot.py`、`scripts/router-network-snapshot.sh`、`scripts/monitoring-log-report.py`。命令模板见 [REFERENCE.md](REFERENCE.md)。
