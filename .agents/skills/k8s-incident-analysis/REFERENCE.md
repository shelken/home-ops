# K8s 事故分析命令参考

> 用占位符替换真实值：`<NS>` `<PROM_SVC>` `<ALERT_SVC>` `<VL_ENDPOINT>` `<START_UTC>` `<END_UTC>` `<METRIC_EXPR>`

## 1) 组件健康与重启

```bash
kubectl -n <NS> get pods -o wide
kubectl -n <NS> get pod <POD> -o json | jq '.status.containerStatuses[] | {name,restartCount,state,lastState}'
kubectl -n <NS> describe pod <POD> | sed -n '/Events:/,$p'
```

关注点：频繁重启、`lastState.terminated.reason`、探针失败、BackOff。

## 2) 探测源日志（先确认故障是否真实发生）

```bash
kubectl -n <NS> logs deploy/<PROBER_DEPLOY> --since-time=<START_UTC>
kubectl -n <NS> logs deploy/<PROBER_DEPLOY> --since-time=<START_UTC> | grep -E '<TARGET>|success=false|timeout|trigger|resolve'
```

结论标准：出现连续失败与恢复日志，且时间与用户反馈一致。

## 3) Prometheus API（不依赖 UI）

```bash
# instant query
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/query?query=<METRIC_EXPR>'

# range query（建议固定 step）
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/query_range?query=<METRIC_EXPR>&start=<START_TS>&end=<END_TS>&step=60s'

# rules / alerts
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/rules'
kubectl -n <NS> get --raw '/api/v1/namespaces/<NS>/services/http:<PROM_SVC>:9090/proxy/api/v1/alerts'
```

关注点：
- 是否有时序（series）
- 值是否跨阈值并持续满足 `for`
- 规则是否 loaded、health 是否 `ok`、lastError 是否为空

## 4) Alertmanager 路由与发送

```bash
kubectl -n <NS> logs <ALERTMANAGER_POD> -c alertmanager --since-time=<START_UTC>
kubectl -n <NS> logs <ALERTMANAGER_POD> -c <NOTIFIER_CONTAINER> --since-time=<START_UTC>
```

关注点：
- 告警是否进入 AM
- 是否命中预期 receiver
- 通知发送是否报错（webhook/slack/telegram 等）

## 5) 聚合日志（VictoriaLogs / LogsQL）

```bash
curl -sG 'http://<VL_ENDPOINT>/select/logsql/query' \
  --data-urlencode 'query=_stream:{app="<APP>",k_namespace_name="<NS>"} "<KEYWORD>" _time:[<START_UTC>,<END_UTC>] | fields _time,_msg' \
  --data-urlencode 'limit=200'
```

实践建议：
- 总是先加 `_time` 范围
- 先 `fields _time,_msg`，再逐步加字段
- 关键词从“组件状态词 + 目标名”组合

## 6) 根因定位判定表

1. 探测失败，Prom 无该指标：抓取/服务发现/Prometheus 异常
2. Prom 指标异常，规则不触发：规则未加载、表达式不匹配、评估中断
3. 规则触发，AM无记录：Prom->AM 通道或配置问题
4. AM有记录，通知无消息：receiver/通知组件故障
5. 监控组件自身高重启/panic：监控平面故障优先级最高

## 7) 常见绕弯（避免）

- 先改 YAML 再取证（高风险）
- 只看当前容器日志，不看 `--previous`
- 时间窗没统一（本地时区 vs UTC）
- 只看 UI，不用 API 做可复现查询
- 把“业务故障”与“监控平面故障”混为一谈
