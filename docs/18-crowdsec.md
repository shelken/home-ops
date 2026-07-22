# CrowdSec 部署与运维指南

## 目标

这份文档记录当前仓库里的 CrowdSec 部署方式、数据流、常用命令和排障入口。公开文档里不写真实域名、公网 IP、内网 IP、节点名、主机名和密钥路径；示例统一使用占位符。

## 当前拓扑

```text
公网请求
  -> VPS Caddy
      -> Caddy CrowdSec bouncer
      -> VPS crowdsec-agent AppSec listener (:7422)
      -> VPS crowdsec-agent 上报事件
  -> 集群 CrowdSec LAPI
      -> PostgreSQL
      -> profile 生成 decision
      -> 通知到 VictoriaLogs / 企业微信
      -> bouncer 拉取 decisions
  -> VPS firewall bouncer / Caddy bouncer 执行拦截
```

关键结论：

- **集群内 CrowdSec 主要是 LAPI + DB + profile + 通知**。
- **VPS 上的 `crowdsec-agent` 才负责读取 VPS Caddy 日志、SSH 日志和 AppSec 检测**。
- **VPS firewall bouncer 才负责把 decisions 写进 VPS iptables/ip6tables**。
- **AppSec 规则排除要写在 VPS compose 的 CrowdSec agent 配置里，不是写在集群 LAPI 里**。

## 代码位置

### 集群 LAPI

```text
k8s/infra/common/security/crowdsec/ks.yaml
k8s/infra/common/security/crowdsec/app/helmrelease.yaml
k8s/infra/common/security/crowdsec/app/externalsecret.yaml
k8s/infra/common/security/crowdsec/app/pvc.yaml
```

### VPS agent / bouncer

```text
compose/vps/docker-compose.yml
compose/vps/configs/crowdsec/acquis.d/all.yaml
compose/vps/configs/crowdsec/crowdsec-firewall-bouncer.yaml
compose/vps/configs/crowdsec/appsec-configs/jellyfin-exclusions.yaml
compose/vps/configs/caddy/Caddyfile
```

## 集群 LAPI 配置

集群 CrowdSec 由 Flux 管理：

```text
Kustomization: security/crowdsec
HelmRelease: security/crowdsec
```

LAPI 使用外部 PostgreSQL：

```yaml
db_config:
  type: postgresql
  user: crowdsec
  db_name: crowdsec
  host: <POSTGRES_SERVICE>
  port: 5432
  sslmode: require
```

LAPI Service 是 LoadBalancer，给 VPS agent / bouncer 访问：

```yaml
lapi:
  service:
    type: LoadBalancer
```

> 具体 LB 地址属于私有信息，文档里不要写死；排查时用 `kubectl -n security get svc crowdsec-service -o wide` 查当前值。

当前集群侧没有启用 agent/appsec：

```yaml
appsec:
  enabled: false
agent:
  enabled: false
```

所以：

```text
集群 LAPI = 中央 API / DB / profile / notification
VPS agent = 实际采集与 AppSec 规则执行
```

## VPS CrowdSec agent

VPS compose 里 `crowdsec-agent` 使用这些 collections：

```text
crowdsecurity/linux
crowdsecurity/caddy
crowdsecurity/http-cve
crowdsecurity/appsec-virtual-patching
crowdsecurity/appsec-generic-rules
crowdsecurity/appsec-crs
```

并禁用本地 LAPI，改连集群 LAPI：

```yaml
DISABLE_LOCAL_API: "true"
LOCAL_API_URL: ${CROWDSEC_LOCAL_API_URL}
AGENT_USERNAME: vps-cc
AGENT_PASSWORD: ${CROWDSEC_AGENT_PASSWORD}
```

VPS agent 的 acquisition：

```yaml
filename: /var/log/caddy/access.log
labels:
  type: caddy
---
filenames:
  - /var/log/auth.log
labels:
  type: syslog
---
appsec_configs:
  - crowdsecurity/appsec-default
  - crowdsecurity/crs
  - local/jellyfin-exclusions
labels:
  type: appsec
listen_addr: 0.0.0.0:7422
source: appsec
```

含义：

- 读取 Caddy access log。
- 读取系统 SSH/auth 日志。
- 对 Caddy 转发来的 AppSec 请求运行默认 AppSec、CRS 和本地排除规则。

## Caddy 集成

VPS Caddy 全局配置里有 CrowdSec：

```caddy
crowdsec {
  api_url {$CROWDSEC_LOCAL_API_URL}
  api_key {$CROWDSEC_CADDY_BOUNCER_API_KEY}
  ticker_interval 15s
  appsec_url http://crowdsec-agent:7422
}
```

站点 route 里先跑 CrowdSec / AppSec，再反代：

```caddy
route {
  crowdsec
  appsec

  # service handlers
}
```

影响：

- 如果 Caddy bouncer 命中 decision，请求会被拦截。
- 如果 AppSec 检测命中 in-band/vpatch，可能直接阻断。
- 如果 AppSec 组件认证失败，Caddy 会在反代前失败，请求不会到 upstream。

## Firewall bouncer

VPS firewall bouncer 使用 iptables：

```yaml
mode: iptables
iptables_chains:
  - INPUT
  - FORWARD
  - DOCKER-USER
deny_action: DROP
```

注意：

- `DROP` 会让客户端表现为超时，而不是明确的 403。
- 因为写入 `DOCKER-USER`，Docker 暴露端口也会受影响。
- 如果自家出口 IP 被 ban，Gatus 访问 VPS 公网域名会 10s timeout，但通过 Tailscale Service 的 TCP 检查可能仍然成功。

## Profiles 与通知

集群 LAPI 里的 profile：

```yaml
name: default_ip_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
  - type: ban
    duration: 4h
notifications:
  - http_victorialogs
  - http_wecom
```

```yaml
name: default_range_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Range"
decisions:
  - type: ban
    duration: 4h
notifications:
  - http_victorialogs
  - http_wecom
```

含义：

- IP / Range 级别 remediation alert 会生成 4h ban。
- 同时写入 VictoriaLogs 和企业微信。

## 常用命令

### 集群 LAPI 状态

```bash
kubectl -n security get pods,svc,pvc | grep crowdsec
kubectl -n security logs deploy/crowdsec-lapi --tail=200
kubectl -n security describe helmrelease crowdsec
```

### 查看 decisions

```bash
kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions list
kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions list -a
```

### 查看 alerts

```bash
kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts list --since 6h
kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts inspect <ALERT_ID> -d
kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts list --ip <IP>
```

### 查看 bouncers

```bash
kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers list
kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers inspect <BOUNCER_NAME>
```

### VPS compose 状态

```bash
task compose:status:vps
ssh <VPS_HOST> 'cd <REMOTE_COMPOSE_DIR> && docker compose ps crowdsec-agent crowdsec-firewall-bouncer caddy'
```

### VPS agent 日志

```bash
ssh <VPS_HOST> 'docker logs crowdsec-agent --since 30m'
ssh <VPS_HOST> 'docker exec crowdsec-agent cscli appsec-configs list'
ssh <VPS_HOST> 'docker exec crowdsec-agent cscli collections list'
```

因为 VPS agent 禁用了本地 LAPI，下面命令在 VPS agent 容器里会失败，这是正常的：

```bash
ssh <VPS_HOST> 'docker exec crowdsec-agent cscli bouncers list'
# local API is disabled
```

要查 bouncer，去集群 LAPI 查。

### VPS firewall bouncer

```bash
ssh <VPS_HOST> 'cd <REMOTE_COMPOSE_DIR> && docker compose logs --tail=200 crowdsec-firewall-bouncer'
ssh <VPS_HOST> 'sudo iptables -S DOCKER-USER | head -80'
ssh <VPS_HOST> 'sudo ip6tables -S DOCKER-USER | head -80'
```

### Caddy access log

Caddy access log 写文件，不走 `docker logs caddy`：

```bash
ssh <VPS_HOST> 'ls -lh /var/log/caddy'
ssh <VPS_HOST> 'tail -n 100 /var/log/caddy/access.log'
```

按错误统计：

```bash
ssh <VPS_HOST> 'python3 - <<'\''PY'\''
import json, time, collections
cutoff = time.time() - 3600
cnt = collections.Counter()
for line in open("/var/log/caddy/access.log", errors="ignore"):
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if obj.get("ts", 0) < cutoff:
        continue
    err = obj.get("error") or ""
    if err:
        cnt[err[:120]] += 1
for err, n in cnt.most_common(20):
    print(n, err)
PY'
```

## 常见故障模式

### 1. Gatus 公网检查超时，但 `vps-caddy` TCP 成功

典型现象：

```text
vps-caddy    success=true
subconverter success=false duration=10s
derp         success=false duration=10s
```

解释：

- `vps-caddy` 检查通常是 `tcp://ts-node-vps.network.svc:443`，走 Tailscale proxy。
- `subconverter` / `derp` 检查公网域名，走 VPS 公网入口。
- 如果 VPS firewall bouncer DROP 了自家出口 IP，公网域名检查会超时，但 Tailscale TCP 检查仍可能成功。

排查：

```bash
kubectl -n observability logs deploy/gatus -c app --since=6h | grep 'group=vps'
kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts list --since 6h
kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts inspect <ALERT_ID> -d
ssh <VPS_HOST> 'grep -F "<HOST>" /var/log/caddy/access.log | tail'
```

### 2. `appsec component not authenticated: 401 Unauthorized`

典型 Caddy error：

```text
appsec component not authenticated: 401 Unauthorized
```

含义：

```text
Caddy -> crowdsec-agent:7422
crowdsec-agent -> 集群 LAPI HEAD /v1/decisions/stream 校验 API key
校验失败或超时
crowdsec-agent 对 Caddy 返回 401
Caddy 不继续 reverse_proxy
```

影响：

- 发生时会影响对应请求。
- 如果只是 crowdsec-agent 重启后的短窗口，Gatus 下一轮可能自动恢复。
- 如果持续出现，重点查 VPS agent 到集群 LAPI 的网络和 LAPI 响应。

排查：

```bash
ssh <VPS_HOST> 'docker logs crowdsec-agent --since 10m | grep -Ei "unauthorized|invalid API key|Error checking auth|decisions/stream"'
kubectl -n security logs deploy/crowdsec-lapi --since=10m | grep 'HEAD /v1/decisions/stream'
ssh <VPS_HOST> 'python3 <CADDY_ERROR_SCAN_SCRIPT>'
```

### 3. AppSec 误判自家出口 IP

典型 alert：

```text
Reason: crowdsecurity/crowdsec-appsec-outofband
Scope:Value: Ip:<HOME_EGRESS_IP>
target_host: <SERVICE_DOMAIN>
target_uri: <SERVICE_PATH>
rule_ids: [<CRS_RULE_IDS>]
```

判断是公共集合还是本地生成：

```bash
kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts inspect <ALERT_ID> -d
kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions list -a | grep '<IP>'
```

- `Kind: crowdsec`、`Machine: vps-cc`、`datasource_type: appsec`：本地 VPS AppSec 生成。
- `Source: CAPI`：来自 CrowdSec Central API 公共情报。

## 自定义 AppSec 排除规则

当前已有 Jellyfin 播放进度接口排除：

```text
compose/vps/configs/crowdsec/appsec-configs/jellyfin-exclusions.yaml
```

内容：

```yaml
name: local/jellyfin-exclusions
pre_eval:
  - filter: IsOutBand == true && req.URL.Path == "/Sessions/Playing/Progress"
    apply:
      - RemoveOutBandRuleByID(932370)
```

选择这个位置的原因：

- 误判发生在 VPS AppSec 规则执行阶段。
- 集群 LAPI 只是接收已生成的 alert/decision。
- 要减少误报源头，必须在 VPS AppSec config 排除具体规则。

不要优先做：

```text
全局 allowlist 自家出口 IP
全局关闭 CRS
全局取消 appsec-outofband ban
```

这些都会扩大安全豁免范围。

## 修改与部署流程

### 修改 VPS CrowdSec 配置

1. 修改 `compose/vps/configs/crowdsec/...`。
2. 本地校验 YAML：

   ```bash
   python3 - <<'PY'
   import yaml
   for p in [
       'compose/vps/configs/crowdsec/acquis.d/all.yaml',
       'compose/vps/docker-compose.yml',
   ]:
       with open(p) as f:
           list(yaml.safe_load_all(f))
       print('ok', p)
   PY
   ```

3. 同步 VPS：

   ```bash
   task compose:sync:vps
   ```

4. 重建 agent：

   ```bash
   ssh <VPS_HOST> 'cd <REMOTE_COMPOSE_DIR> && docker compose up -d crowdsec-agent'
   ```

5. 验证：

   ```bash
   ssh <VPS_HOST> 'docker exec crowdsec-agent cscli appsec-configs list'
   ssh <VPS_HOST> 'docker logs crowdsec-agent --since 2m | grep -i appsec'
   ```

注意：`task compose:sync:vps` 会临时生成 `.env` 和模板渲染文件。命令中断后要确认本地没有残留敏感文件：

```bash
test -f compose/vps/.env && echo 'WARN .env exists' || echo '.env absent'
```

## 外部参考

- CrowdSec AppSec 配置语法：<https://docs.crowdsec.net/docs/next/appsec/configuration>
- CrowdSec AppSec hooks：<https://docs.crowdsec.net/docs/next/appsec/hooks.md>
- CrowdSec AppSec 自定义配置与测试：<https://docs.crowdsec.net/docs/next/appsec/configuration_creation_testing/>
- CrowdSec profiles：<https://docs.crowdsec.net/docs/next/profiles/format>
