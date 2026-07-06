# envoy geoip inplace mmdb reload

**日期**: 2026-07-06
**影响**: 外部入口经 Envoy Gateway 访问多个服务时，间歇性返回 403；部分 Gatus external 探测持续失败。
**发现人**: 用户

## 问题

GeoIP 数据库更新任务只在一个节点上更新 hostPath 中的 MaxMind mmdb 文件，并且直接覆盖 Envoy 正在读取的目标文件。运行中的 Envoy Gateway Pod 在热重载该 mmdb 后，GeoIP / RBAC 匹配状态异常，本应被 CN/HK GeoIP 规则放行的请求落入默认 Deny，返回 403。

## 现象

Victoria Logs 中 Envoy access log 显示：

```text
response_code=403
response_code_details=rbac_access_denied_matched_policy[DENY]
```

故障边界非常清楚：

```text
18:55 UTC  external Gatus 探测无 403
18:58 UTC  external Gatus 探测无 403
19:00 UTC  geoip-updater 旧 CronJob 定时触发，只更新调度到的一个节点
19:01 UTC  同一 Envoy 旧 Pod 立刻出现多次 403
之后持续到该旧 Pod 被删除
删除旧 Pod 后，新 Pod 从完整 mmdb 启动，403 消失
```

同一批 Host 不是恒定失败，而是大多 403、偶尔 200，说明不是静态 YAML 写成永远拒绝，而是运行时 GeoIP/RBAC 匹配状态异常。

## 根因

### 技术根因

1. **更新模型错误**：旧 `geoip-updater` 是 CronJob，只会在调度到的一个节点执行；但 Envoy 使用每节点 hostPath mmdb，实际需求是每个节点都有一份最新数据库。
2. **重复任务造成判断混乱**：集群里同时存在另一个 namespace 下的旧 `geoip-updater` CronJob，来源不是当前仓库源码；它和网络组件的 updater 同时运行，但这只是集群漂移，不是可靠的“每节点更新”设计。
3. **写入方式危险**：任务直接写正式 mmdb 文件。Envoy 1.38.3 支持 MaxMind mmdb 热重载，运行中的 Envoy 可能在文件被覆盖期间触发 reload。
3. **授权语义变窄**：迁移到原生 `SecurityPolicy` 后，`allow-unknown-location` 从“没有 GeoIP country header 就允许”变成了“只允许私网/本机 CIDR”。当 GeoIP provider 或内部 header 异常时，公网请求会落入 default Deny。
4. **可观测性不足**：Gatus 能看到 external 失败，但告警等待时间偏长，且没有直接提示先查 Envoy access log 的 `response_code_details`。

### 排查错误

1. **过早归因到 DB 内容差异**：后续验证两节点最终 DB 内容一致，且都能把客户端公网 IP 判定为预期国家/地区。
2. **误判 Envoy 不热重载**：Envoy 1.38.3 已支持 MaxMind mmdb 热重载，问题不是“不热重载”，而是热重载期间/之后运行时状态异常。
3. **误判只有单节点异常**：Victoria Logs 扩大查询后发现主要异常集中在一个旧 Pod，但另一个旧 Pod 也有少量 403。
4. **把修复尝试误读成故障时状态**：后续 Indexed Job 注释写着“每个节点各跑一个 Pod”，但该修复提交晚于故障触发时间；它不能解释故障发生时的行为。
5. **未第一时间保留旧 Pod 证据**：旧 Pod 删除后，无法再抓当时的 config_dump、stats 和 debug 日志，只能靠历史日志和时间线还原。

## 修复

已做声明式修复：

1. `geoip-updater` 从 CronJob/Indexed Job 改为 DaemonSet：每个 Linux 节点一个 updater Pod，天然覆盖当前和未来新增节点。
2. 下载 mmdb 先写 `.tmp` 文件，再 `mv` 原子替换正式文件，避免 Envoy 看到下载中的半文件。
3. 不再 patch/restart Envoy，也不再需要更新任务持有 Kubernetes RBAC 权限。
4. Gatus external 告警从 `for: 5m` 缩短到 `for: 1m`，并在告警描述中提示优先查 Envoy access log 的 `response_code_details`。
5. 修正 `SecurityPolicy` 注释，明确当前原生写法只放行私网/本机 CIDR，不等价旧 `unknown GeoIP` 放行。

## 预防

1. **每节点文件用 DaemonSet，不用单 Pod CronJob。** 只要数据落在 node-local hostPath，更新控制器就应该表达“每节点一份”。
2. **被运行时热加载的文件必须原子替换。** 下载、解压、校验都写临时文件；只有完整文件准备好后才 `mv` 到正式路径。
3. **迁移授权策略时必须对照 deny/unknown 语义。** 原生 API 不能表达旧 RBAC 的 absent/not-present 时，不能把“近似写法”标成等价。
4. **删除异常 Pod 前先抓证据。** 至少保存 access log、config_dump、相关 stats、最近 reload 日志；恢复动作可以做，但证据先留。
5. **external 入口失败先看 Envoy `response_code_details`。** 403 + `rbac_access_denied_matched_policy[DENY]` 应立即进入 GeoIP/RBAC 排查路径。
