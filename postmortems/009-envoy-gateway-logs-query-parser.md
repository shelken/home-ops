# Envoy Gateway 访问日志查询语法回退

**日期**: 2026-06-22
**影响**: Grafana 中 Envoy Gateway 访问日志面板报错，部分变量请求也会失败。
**发现人**: pi

## 问题
VictoriaLogs 升级后，Envoy Gateway 访问日志仪表盘里带特殊字符字段名的 LogsQL 继续沿用旧写法，Grafana 插件在查询阶段报错，面板无法正常打开。

## 现象
- Grafana 后端日志里出现 `cannot read regexp for field ...`。
- 直接打 VictoriaLogs 的查询有时能成功，但 Grafana 的 `queryData` 路径仍会失败。
- 反复尝试把字段名整体加引号、换单引号、换反引号，都没有解决问题。

## 根因
- 把几种不同问题混在一起看：字段名 quoting、变量展开、`_msg` 过滤方式。
- `:authority` 不能裸写，也不能靠当前插件的 quoted field name 跑通。
- `requested_server_name` 和 `:authority` 在这批 Envoy 日志里对应同一个值，可直接用前者保留筛选语义。
- `domain` / `response_code` 是 field value 变量，不应放进 regexp filter；VictoriaLogs Grafana datasource 要用 `field:$var` / `field:=$var`，由插件展开成 `field:in(...)`。

## 修复
- panel query 改成：
  - `user-agent:!~"(Vector|Gatus|Uptime-Kuma).*"`
  - `requested_server_name:$domain`
  - `response_code:$response_code`
  - `x-envoy-origin-path:~"${path:regex}"`
  - `downstream_remote_address:!~"(${exclude_ips}).*"`
- 用 Grafana `api/ds/query` 验证新 expr 能返回 200，且最近日志无 `cannot parse query arg`。
- 外部 dashboard repo 删除 3 个无效修复提交，改为单个有效修复提交。

## 预防
- 先用最小 query 验证字段语法，再拼完整 dashboard。
- 遇到特殊字符字段名，先判断能否直接裸写；能用同义字段时，优先换成无特殊字符那一个。
- field value 变量默认用 `field:$var`；只有真正来自 textbox 的正则输入才放进 regexp filter。
- 不要把同一类错误都归到 VictoriaLogs 解析器上，先区分是直连查询、Grafana 插件，还是 dashboard 变量展开。
