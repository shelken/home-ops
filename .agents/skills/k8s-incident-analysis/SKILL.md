---
name: k8s-incident-analysis
description: 提供基于取证的 Kubernetes 事故排查流程，覆盖近期升级/镜像回退、Gatus、Prometheus、Alertmanager、Victoria Logs，以及家宽出口、路由器、代理 DNS 旁路取证。Use when 用户反馈“服务离线但没告警”、升级后异常、K8s 应用/入口/备份链路失败、Gatus/Prometheus/Alertmanager 异常、router-dns-proxy 延迟/失败、外部访问抖动，或需要统一时间线定位故障断点时。
---

# K8s Incident Analysis

## Quick start

目标：先确认近期变更，再建立统一时间线，最后判断断点在应用、入口、探测、采集、规则、路由、通知，还是集群外网络。

开始前先读 [REFERENCE.md](REFERENCE.md) 的实用命令；涉及家宽出口、代理 DNS 或路由器时，优先运行 `scripts/router-network-snapshot.sh` 收集现场。

1. 定义故障窗口，统一到 UTC。
2. 明确故障服务/链路，先查 GitOps 配置、当前运行镜像、最近 Renovate/升级 PR 和上游 release；服务刚升级时优先验证回归。
3. Gatus 未持久化时，先跑 `scripts/gatus-runtime-snapshot.py` 看本次启动以来的内存结果和失败时间线。
4. 历史日志优先查 Victoria Logs；`kubectl logs` 只补当前/previous 容器细节。
5. 先确认业务或探测器是否真的看到失败，再查 Prometheus 时序与规则。
6. Alertmanager 不只看发件端日志，还要对照 receiver/接收端日志。
7. 如果业务路径经过路由器、代理 DNS、WAN/WWAN，再开一条“集群外网络旁路”并行排查。
8. 输出时间线、断点位置、排除依据；不先改 YAML，确认升级回归后再给 GitOps 回退方案。

## Workflows

### 1) 建立时间线（必须先做）

- 记录用户观察到的开始、自动恢复、人工干预、恢复时间。
- 每条证据都带时间戳和时区。
- 区分“业务故障”和“监控平面故障”。

### 2) 最近变更排查（业务服务先做）

- 对齐三件事：GitOps 期望版本、集群当前运行镜像、故障窗口前后的 Renovate/升级 PR。
- 如果错误服务近期升级过，优先查上游 release、merged/open PR、精确错误关键词；把“升级回归”排在假设前列。
- 回退不是默认动作；必须先用日志、PR diff/release note、版本差异证明当前错误与升级相关。

### 3) 六段排查（五段主链路 + 一条旁路）

1. **探测段**：Gatus / blackbox / sidecar 是否持续失败
2. **采集段**：Prometheus 是否真的抓到了对应时序
3. **规则段**：规则是否 loaded、health 是否正常、是否满足 `for`
4. **路由段**：Alertmanager 是否命中正确 receiver
5. **通知段**：接收端是否真的收到/处理 webhook
6. **外部网络旁路**：路由器、代理 DNS、WAN/WWAN、上游 DNS / 无线中继是否抖动

### 4) 实战规则

- Gatus 无 storage 时，API 只代表本次启动以来窗口；先记录 window_start/window_end，再解释失败次数。
- `Prometheus 没有时序` 不等于 `故障没发生`；先排除抓取缺口、Pod 重建、监控盲区。
- `Alertmanager 有发送成功` 不等于 `最终动作生效`；必须对照接收端日志。
- Gatus DNS 检测里，要区分 **真实解析超时** 和 `[RESPONSE_TIME]` 这个**成功阈值**。
- 普通公网 RTT 正常，不代表代理 DNS 正常；DNS、代理、出口要拆开测。
- 历史日志/跨 Pod 时间线尽量用聚合日志，不要只盯当前容器 stdout。

## Output format

结论必须包含：

- 3~8 个关键时间点
- 断点位置（应用/入口/六段链路中的哪一段）
- 最近变更/升级 PR 判断：有无关联、是否建议回退
- 证据命令与关键输出
- “为什么不是其它段”的排除依据
- 如涉及路由器/出口，单独说明是 **基础出网**、**DNS**、**代理 DNS** 还是 **无线链路** 的问题

## Advanced

先看 [REFERENCE.md](REFERENCE.md) 里的实用命令，再按需运行 `scripts/gatus-runtime-snapshot.py`、`scripts/router-network-snapshot.sh`。
