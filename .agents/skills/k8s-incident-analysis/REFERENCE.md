# K8s 事故分析命令参考

> 用占位符替换真实值：`<NS>` `<PROM_SVC>` `<ALERT_POD>` `<VL_ENDPOINT>` `<START_UTC>` `<END_UTC>` `<ALERTNAME>` `<ROUTER_HOST>`。

## 0) 使用原则

1. 先统一故障窗口，再查任何日志或指标。
2. 历史日志优先 Victoria Logs；`kubectl logs` 主要补当前容器和 `--previous`。
3. 先确认“真实故障是否发生”，再判断是监控链路坏了还是业务本身坏了。
4. 只看一个面会误判：日志、指标、规则、发送端、接收端至少交叉两面。
5. 涉及外部访问、代理 DNS、家宽出口时，必须补一条路由器旁路线。

## 1) 组件健康与重启

```bash
kubectl -n <NS> get pods -o wide
kubectl -n <NS> get pod <POD> -o json | jq '.status.containerStatuses[] | {name,restartCount,state,lastState}'
kubectl -n <NS> describe pod <POD> | sed -n '/Events:/,$p'
```

关注点：频繁重启、`lastState.terminated.reason`、探针失败、BackOff、Pod 重建导致的日志/指标断面。

## 2) Victoria Logs：先建历史时间线

```bash
curl -sG 'http://<VL_ENDPOINT>/select/logsql/query' \
  --data-urlencode 'query=_stream:{k_namespace_name="<NS>"} _time:[<START_UTC>,<END_UTC>] | fields _time,_msg,k_pod_name,k_container_name' \
  --data-urlencode 'limit=200'
```

常用缩小范围方式：

```bash
# 只看某个 Pod / 容器
curl -sG 'http://<VL_ENDPOINT>/select/logsql/query' \
  --data-urlencode 'query=_stream:{k_namespace_name="<NS>",k_pod_name=~"gatus.*",k_container_name="app"} "success=false" _time:[<START_UTC>,<END_UTC>] | fields _time,_msg' \
  --data-urlencode 'limit=200'

# 只看某个动作接收端
curl -sG 'http://<VL_ENDPOINT>/select/logsql/query' \
  --data-urlencode 'query=_stream:{k_namespace_name="network",k_pod_name=~"passwall-healer.*"} "passwall" _time:[<START_UTC>,<END_UTC>] | fields _time,_msg' \
  --data-urlencode 'limit=200'
```

实践建议：

- 总是先加 `_time` 范围。
- 先 `fields _time,_msg`，再逐步加字段。
- 关键词优先用“组件状态词 + 目标名”，例如：`success=false`、`Notify success`、`BEACON-LOSS`、`router-dns-proxy`。
- Victoria Logs 返回的是 **stream+json**，通常是一行一个 JSON，不要假设它是普通数组 JSON。

## 3) 探测段：Gatus / blackbox

```bash
kubectl -n <NS> logs deploy/<PROBER_DEPLOY> --since-time=<START_UTC>
kubectl -n <NS> logs deploy/<PROBER_DEPLOY> --since-time=<START_UTC> \
  | grep -E '<TARGET>|success=false|timeout|trigger|resolve'
```

Gatus 相关经验：

- `router-dns-proxy` 这种 DNS 检测，先分清是 **真实解析慢/超时**，还是你配置的 `[RESPONSE_TIME] < N` 成功阈值过紧。
- 对 DNS 端点来说，`[CONNECTED] == true`、`[DNS_RCODE] == NOERROR`、`[RESPONSE_TIME]` 是三类不同信号，不要混成一个结论。
- 如果需要对历史多 Pod 时间线做统计，优先用 Victoria Logs，不要只看当前 `kubectl logs`。

## 4) Prometheus API：不要只看 UI

```bash
# instant query
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/query?query=<METRIC_EXPR>'

# range query
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/query_range?query=<METRIC_EXPR>&start=<START_TS>&end=<END_TS>&step=60s'

# rules / alerts
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/rules'
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/alerts'
```

常用查询模板：

```promql
gatus_results_endpoint_success{group="router",name="router-dns-proxy"}
changes(gatus_results_endpoint_success{group="router",name="router-dns-proxy"}[24h])
1 - avg_over_time(gatus_results_endpoint_success{group="router",name="router-dns-proxy"}[24h])
ALERTS{alertname="<ALERTNAME>",alertstate="firing"}
up{job="gatus"}
scrape_samples_scraped{job="gatus"}
```

这次排障学到的判定要点：

- `Prometheus 没有时序` 不等于 `故障没发生`。
- 先对照：
  1. 目标 Pod 的 `startTime`
  2. 探测器自身日志
  3. `up{job="..."}` 或 `scrape_samples_scraped{job="..."}`
- 如果应用日志有历史事件，但 Prometheus 只在更晚时间才出现样本，先判定为 **抓取盲区/监控面缺口**，而不是业务没故障。
- 查规则时不要只看表达式，要看 `health`、`lastError` 和 `for` 是否真能满足。

## 5) Alertmanager：发件端与收件端必须成对看

```bash
kubectl -n <NS> logs <ALERT_POD> -c alertmanager --since-time=<START_UTC>
kubectl -n <NS> logs <ALERT_POD> -c alertmanager --since=168h | grep 'receiver='
```

重点 grep：

```bash
grep 'Notify success'
grep 'Notify attempt failed'
grep 'receiver='
grep '<ALERTNAME>'
```

常见判定：

- `Notify attempt failed`：看是 TLS handshake timeout、connection reset、500，还是路由错误。
- `Notify success`：只能证明 **Alertmanager 已经发出**，不能证明 webhook 接收端真的执行成功。
- 必须对照接收端日志，例如 `passwall-healer`、`zte-mifi-healer`、通知机器人等。

接收端对照示例：

```bash
kubectl -n network logs deploy/passwall-healer --since=24h
kubectl -n network logs deploy/zte-mifi-healer --since=24h
```

如果出现“AM 日志很少，但接收端收到很多 POST”，优先怀疑：

- 触发源不止 Alertmanager 一处
- 观察时间窗不一致
- grep 关键词过窄
- 你正在看错容器/错 Pod/错时间

## 6) 路由器与出口旁路线

当问题涉及外部 API 超时、`router-dns-proxy`、家宽出口、代理 DNS、Wi‑Fi 中继时，补这条旁路线。

### 6.1 一键快照

```bash
scripts/router-network-snapshot.sh <ROUTER_HOST>
```

可选环境变量：`WWAN_GW` `WAN_GW` `TEST_IP` `PROXY_DOMAIN` `DIRECT_DOMAIN` `UPSTREAM_DNS`。

### 6.2 监控链路日志汇总

编写原则：

- 脚本只负责**统一时间窗、找到入口、取日志**。
- 不在脚本里做消息内容过滤，不内置告警场景，不把本次事件写死。
- 过滤动作放在脚本外面，用 `rg`、`grep`、`jq`、`sed` 自己接。
- 这样脚本才能长期复用，不会因为新场景越来越臃肿。

```bash
# 先把同一时间窗的几段日志拿出来
python3 scripts/monitoring-log-report.py \
  --hours 6 \
  --vl-endpoint 192.168.69.66:9428 \
  --vl-section 'name=gatus,namespace=observability,pod=gatus.*' \
  --kubectl-section 'name=alertmanager,namespace=observability,selector=app.kubernetes.io/name=alertmanager,container=alertmanager' \
  --vl-section 'name=receiver,namespace=network,pod=passwall-healer.*'

# 再按自己需要过滤
python3 scripts/monitoring-log-report.py \
  --hours 6 \
  --vl-endpoint 192.168.69.66:9428 \
  --vl-section 'name=gatus,namespace=observability,pod=gatus.*' \
  --vl-section 'name=receiver,namespace=network,pod=passwall-healer.*' \
  | rg 'router-dns-proxy|success=false|passwall'

# 只看某一段入口也可以
python3 scripts/monitoring-log-report.py \
  --hours 24 \
  --vl-endpoint 192.168.69.66:9428 \
  --skip-kubectl \
  --vl-section 'name=receiver,namespace=network,pod=passwall-healer.*'
```

这个脚本的职责只有两件事：

1. 把重复的 Victoria Logs / `kubectl logs` 入口命令收起来
2. 让不同来源的日志落在同一个时间窗里

适合先把原始日志拿出来，再用管道做第二步分析。

### 6.3 手工最小命令集


```bash
ssh <ROUTER_HOST> 'ip route show default; ip rule show; ubus call network.interface dump'
ssh <ROUTER_HOST> 'iw dev; iw dev <STA_IF> link; iw dev <STA_IF> station dump'
ssh <ROUTER_HOST> 'ping -c 10 -W 1 -I <WWAN_IF> <WWAN_GW>; ping -c 10 -W 2 -I <WWAN_IF> <TEST_IP>'
ssh <ROUTER_HOST> 'ping -c 10 -W 1 -I <WAN_IF> <WAN_GW>; ping -c 10 -W 2 -I <WAN_IF> <TEST_IP>'
ssh <ROUTER_HOST> 'nslookup <PROXY_DOMAIN> 127.0.0.1; nslookup <DIRECT_DOMAIN> 127.0.0.1'
ssh <ROUTER_HOST> 'logread | grep -Ei "BEACON-LOSS|wpa_supplicant|passwall|sing-box|chinadns-ng|dnsmasq" | tail -n 120'
```

### 6.4 代理 DNS 链路固定检查项

如果是 Passwall / chinadns-ng / sing-box：

```text
53 -> 15355 -> 15353
```

检查点：

```bash
ssh <ROUTER_HOST> 'netstat -lntup 2>/dev/null | grep -E "127\.0\.0\.1:15353|:15355|:53 "'
ssh <ROUTER_HOST> 'pidof sing-box; pidof chinadns-ng'
```

判定经验：

- `53` 正常、`15355` 正常，不代表 `15353` 正常。
- 直连域名能解析，不代表代理域名正常。
- 普通公网 RTT 正常，不代表代理 DNS 正常。

### 6.5 Wi‑Fi 中继 / WWAN 的判定经验

重点看：

- `iw dev <STA_IF> station dump` 的 `tx retries`、`tx failed`、`beacon loss`
- `logread` 里的 `CTRL-EVENT-BEACON-LOSS`
- `ping <WWAN_GW>` vs `ping <TEST_IP>`
- `nslookup <DOMAIN> 127.0.0.1` vs `nslookup <DOMAIN> <WWAN_GW>`

解释方式：

1. `ping <WWAN_GW>` 正常，但 `<WWAN_GW>` 的 DNS 固定慢：上游路由器 DNS 差。
2. `ping <WWAN_GW>` 自己就抖，同时有 `BEACON-LOSS`：无线中继链路差。
3. 普通 RTT 正常，但本地 `127.0.0.1` 查代理域名慢：本地代理 DNS 栈或其上游慢。
4. `wwan` 比 `wan` 普通 RTT 更低，不代表它的上游 DNS 更好；基础出网与 DNS 质量要分开判断。

## 7) 扩展判定表

1. 探测失败，Prom 无该指标：抓取/服务发现/Prometheus 异常，或监控盲区。
2. Prom 指标异常，规则不触发：规则未加载、表达式不匹配、`for` 不满足、评估中断。
3. 规则触发，AM 无记录：Prom->AM 通道或查询时间窗错误。
4. AM 有 `Notify success`，接收端无记录：日志窗口不对、看错目标，或发件端成功但目标服务前还有其它中间层。
5. AM 有记录，接收端也有记录，但动作无效：接收端业务逻辑失败或幂等判断吞掉了动作。
6. 集群内 HTTP/ICMP 正常，但外部域名/DNS 慢：优先查路由器、代理 DNS、上游 DNS、WAN/WWAN。
7. 监控组件高重启 / scrape 全面缺口：优先判定为监控平面故障。

## 8) 常见绕弯

- 先改 YAML 再取证。
- 只看当前容器日志，不看 `--previous` 或聚合日志。
- Prometheus 没样本就断言“故障没发生”。
- 只看 Alertmanager 发件端，不看 receiver / webhook 接收端。
- 把 `[RESPONSE_TIME]` 阈值问题误判为 DNS 服务完全不可用。
- 只看公网 ping，不拆 DNS / 代理 DNS / 上游 DNS / 无线中继。
- 把集群内网关地址误当成家里物理路由器。
- 时间窗没统一（本地时区 vs UTC），导致对不上自动恢复动作。
