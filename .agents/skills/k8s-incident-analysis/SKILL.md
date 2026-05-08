---
name: k8s-incident-analysis
description: 提供 Kubernetes 事故排查的标准化取证流程，快速定位问题卡在探测、采集、规则、路由还是通知链路。Use when 用户反馈“服务离线但没告警”、"Prometheus/Alertmanager 没通知"、需要在集群中基于日志与指标做根因分析时。
---

# K8s Incident Analysis

## Quick start

目标：先定位“哪一段链路断了”，再决定修复，不先改配置。

1. 定义故障窗口（开始/恢复时间，统一时区）
2. 查探测源日志（例如 gatus/blackbox）确认“真实故障是否发生”
3. 查 Prometheus 是否采到对应时序
4. 查规则是否已加载且持续评估
5. 查 Alertmanager 路由/接收器是否接到告警
6. 输出时间线和断点结论

## Workflows

### 1) 建立时间线（必须先做）

- 记录：故障开始、用户干预、恢复时间
- 统一到 UTC 或集群时区，避免错窗
- 每条证据都带时间戳

### 2) 五段链路排查（从前往后）

1. **探测段**：探测器日志里是否持续失败
2. **采集段**：Prometheus 是否存在对应指标序列和值变化
3. **规则段**：目标告警规则是否 loaded、health 是否异常
4. **路由段**：Alertmanager 是否命中预期 receiver
5. **通知段**：通知组件日志是否实际发送/失败

### 3) 并行取证清单

- Pod 健康：`restartCount`、`lastState`、`events`
- 组件日志：当前容器 + `--previous`
- 指标查询：`query` + `query_range` + `rules`
- 日志聚合：按 `_time` 范围精确过滤，不扫全量

## Decision matrix

- 探测失败 + 指标缺失：采集链路问题（抓取/服务发现/Prometheus不稳）
- 指标异常 + `ALERTS` 无触发：规则链路问题（规则未加载/评估中断）
- `ALERTS` 已触发 + 无通知：路由或通知链路问题
- 监控组件高重启/崩溃：优先判定为“监控平面故障”

## Output format

结论必须包含：

- 故障时间线（3~8个关键时间点）
- 断点位置（五段链路中的哪一段）
- 证据命令与关键日志片段
- “为什么不是其它段”的排除依据

## Advanced

常用命令模板与查询语句见 [REFERENCE.md](REFERENCE.md)。
