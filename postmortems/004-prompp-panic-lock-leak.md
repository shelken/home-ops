# Prom++ panic lock leak

**Date**: 2026-05-10
**Impact**: 监控平面降级；Prometheus API 查询卡死，告警评估与通知可靠性下降。Prometheus Pod 曾重启 54 次，随后进程半存活但核心查询路径不可用。
**Discovered by**: 用户反馈 Prom++ `counter cannot decrease in value` panic；后续通过当前容器日志、Prometheus HTTP API、pprof goroutine、宿主机进程检查确认。

## Problem

`prompp/prompp:0.8.0-rc2` 在采集写 WAL 路径触发 `counter cannot decrease in value` panic。进程没有立即完全退出，而是在 panic 展开期间卡在 deferred report/append 路径，导致 WAL/Head 相关锁长期持有。

结果：

- `/api/v1/query?query=up` 60s 超时。
- `/api/v1/status/tsdb`、`/api/v1/labels` 超时。
- `/metrics` 仍能响应，造成“进程活着但数据查询坏了”的假象。
- rollout 到旧版本时，旧僵死 `prompp` 进程继续持有 `/prometheus/lock`，新容器先进入 CrashLoopBackOff。

## Symptoms

最小复现/确认命令：

```bash
kubectl -n <NAMESPACE> logs <PROMETHEUS_POD> -c prometheus --tail=200
kubectl -n <NAMESPACE> get pod <PROMETHEUS_POD> -o jsonpath='{range .status.containerStatuses[*]}{.name}{" restarts="}{.restartCount}{" ready="}{.ready}{"\n"}{end}'
```

关键历史崩溃：

```text
panic: counter cannot decrease in value
  github.com/prometheus/client_golang/prometheus.(*counter).Add
  github.com/prometheus/prometheus/pp/go/cppbridge.walPrometheusScraperHashdexParse
```

当前容器卡死证据：

```bash
curl -m 60 'http://127.0.0.1:<PORT>/api/v1/query?query=up'
# timeout

curl -m 20 'http://127.0.0.1:<PORT>/api/v1/status/tsdb'
# timeout
```

pprof 关键栈：

```text
github.com/prometheus/client_golang/prometheus.(*counter).Add
github.com/prometheus/prometheus/pp/go/cppbridge.headWalEncoderFinalize
github.com/prometheus/prometheus/pp/go/storage/head/shard/wal.(*Wal).Commit
github.com/prometheus/prometheus/pp-pkg/scrape.(*scrapeLoop).scrapeAndReport
```

锁/卡死证据：

```text
Rotator.rotate -> LockWithPriority  等待数千分钟
Wal.Write / Wal.Commit              等待同一 mutex
/api/v1/query code="499"             大量客户端取消
```

rollout 后 CrashLoop 证据：

```text
opening storage failed: lock DB directory: resource temporarily unavailable
```

宿主机确认旧进程持锁：

```bash
sudo fuser -v /var/lib/kubelet/pods/<POD_UID>/volumes/.../prometheus-db/lock
# old prompp PID holds lock
```

## Root cause

技术根因：

1. Prom++ 0.8.0-rc2 的 WAL/C++ bridge 计数路径会把负值传给 Prometheus Counter，触发 `counter cannot decrease in value`。
2. `Wal.Commit()` 在 `encLocker.Lock()` 后调用 `encoder.Finalize()`；该调用 panic 时没有 `defer` 释放锁，造成 WAL encoder mutex 泄漏。
3. panic 发生在 scrape path 的 deferred report 周期内，进程进入半死状态：HTTP/metrics 部分仍活，Head/WAL/query path 卡死。
4. 新版本 rollout 时旧半死进程没有及时消失，继续持有 TSDB lock，新 0.7.8 容器无法打开 `/prometheus`。

排查过程根因：

1. 过早相信上一轮 handoff 的“时间回退是主因”，先检查/修改时间同步，而不是先检查当前容器的 pprof 与查询路径。
2. 把 `--previous` 崩溃日志当作当前状态证据，漏掉“当前容器半死但未退出”的状态。
3. 先看 readiness/restart，没立刻验证 `query=up`、`status/tsdb` 这些用户真正依赖的功能路径。
4. rollout CrashLoop 后先解释为旧锁文件，直到 `fuser` 才确认旧 prompp 进程仍持有文件锁。

## Fix

已执行：

1. GitOps 回退 Prom++：

   ```text
   k8s/infra/common/observability/kube-prometheus-stack/app/helmrelease.yaml
   prompp/prompp:0.8.0-rc2 -> prompp/prompp:0.7.8
   ```

2. 提交：

   ```text
   a94e183a fix(observability): downgrade prompp to 0.7.8
   ```

3. rollout 后发现 TSDB lock 被旧进程占用，定位并终止旧 prompp PID：

   ```bash
   sudo fuser -v <PROMETHEUS_DB_LOCK>
   sudo kill -TERM <OLD_PROMPP_PID>
   sudo kill -KILL <OLD_PROMPP_PID>
   ```

4. 当前验证结果：

   ```text
   <PROMETHEUS_POD> 2/2 Running
   prometheus ready=true restarts=0
   container image: prompp/prompp:0.7.8
   ```

## Prevention

以后同类问题按以下顺序执行：

1. 先查当前容器，不先看 `--previous`：

   ```bash
   kubectl -n <NAMESPACE> logs <PROMETHEUS_POD> -c prometheus --since=30m
   kubectl -n <NAMESPACE> get pod <PROMETHEUS_POD> -o jsonpath='{.status.containerStatuses}'
   ```

2. 对 Prometheus 类故障，必须验证功能路径：

   ```bash
   curl -m 10 'http://127.0.0.1:<PORT>/-/ready'
   curl -m 10 'http://127.0.0.1:<PORT>/api/v1/query?query=1'
   curl -m 60 'http://127.0.0.1:<PORT>/api/v1/query?query=up'
   curl -m 20 'http://127.0.0.1:<PORT>/api/v1/status/tsdb'
   ```

3. 如果进程活着但查询超时，立刻抓 pprof：

   ```bash
   curl -m 10 'http://127.0.0.1:<PORT>/debug/pprof/goroutine?debug=2'
   ```

4. 遇到 `lock DB directory: resource temporarily unavailable`，不要只删 lock 文件；先查持锁进程：

   ```bash
   sudo fuser -v <PROMETHEUS_DB_LOCK>
   sudo pgrep -af '/bin/prompp|/bin/prometheus'
   ```

5. 对 prerelease 监控核心组件，升级前必须看 release note 与历史回退记录；Prom++ 0.8.x 需要单独列为高风险。

6. 任何临时宿主机改动必须记录：本次曾给 Lima guestagent 加 systemd drop-in 禁止 `CAP_SYS_TIME`，它解决时间回退噪声，但不是 Prom++ 卡死根因。
