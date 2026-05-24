---
name: k8s-incident-analysis
description: 提供基于取证的 Kubernetes 监控事故排查流程，覆盖 Gatus、Prometheus、Alertmanager、Victoria Logs，并在问题延伸到家宽出口、路由器、代理 DNS 时提供旁路线取证方法。Use when 用户反馈“服务离线但没告警”、"Gatus/Prometheus/Alertmanager 异常"、"router-dns-proxy 延迟/失败"、外部访问抖动，或需要统一时间线定位故障断点时。
---

# K8s Incident Analysis

## Quick start

目标：先建立统一时间线，再判断断点在探测、采集、规则、路由、通知，还是集群外网络。

开始前先读 [REFERENCE.md](REFERENCE.md) 的实用命令；涉及家宽出口、代理 DNS 或路由器时，优先运行 `scripts/router-network-snapshot.sh` 收集现场。

1. 定义故障窗口，统一到 UTC。
2. 历史日志优先查 Victoria Logs；`kubectl logs` 只补当前/previous 容器细节。
3. 先确认探测器是否真的看到失败，再查 Prometheus 时序与规则。
4. Alertmanager 不只看发件端日志，还要对照 receiver/接收端日志。
5. 如果业务路径经过路由器、代理 DNS、WAN/WWAN，再开一条“集群外网络旁路”并行排查。
6. 输出时间线、断点位置、排除依据，不先改 YAML。

## Workflows

### 1) 建立时间线（必须先做）

- 记录用户观察到的开始、自动恢复、人工干预、恢复时间。
- 每条证据都带时间戳和时区。
- 区分“业务故障”和“监控平面故障”。

### 2) 六段排查（五段主链路 + 一条旁路）

1. **探测段**：Gatus / blackbox / sidecar 是否持续失败
2. **采集段**：Prometheus 是否真的抓到了对应时序
3. **规则段**：规则是否 loaded、health 是否正常、是否满足 `for`
4. **路由段**：Alertmanager 是否命中正确 receiver
5. **通知段**：接收端是否真的收到/处理 webhook
6. **外部网络旁路**：路由器、代理 DNS、WAN/WWAN、上游 DNS / 无线中继是否抖动

### 3) 实战规则

- `Prometheus 没有时序` 不等于 `故障没发生`；先排除抓取缺口、Pod 重建、监控盲区。
- `Alertmanager 有发送成功` 不等于 `最终动作生效`；必须对照接收端日志。
- Gatus DNS 检测里，要区分 **真实解析超时** 和 `[RESPONSE_TIME]` 这个**成功阈值**。
- 普通公网 RTT 正常，不代表代理 DNS 正常；DNS、代理、出口要拆开测。
- 历史日志/跨 Pod 时间线尽量用聚合日志，不要只盯当前容器 stdout。

## Output format

结论必须包含：

- 3~8 个关键时间点
- 断点位置（六段中的哪一段）
- 证据命令与关键输出
- “为什么不是其它段”的排除依据
- 如涉及路由器/出口，单独说明是 **基础出网**、**DNS**、**代理 DNS** 还是 **无线链路** 的问题

## Advanced

先看 [REFERENCE.md](REFERENCE.md) 里的实用命令，再按需运行 `scripts/router-network-snapshot.sh`。
