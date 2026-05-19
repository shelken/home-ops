# CrowdSec AppSec self ban blocks VPS probes

**日期**: 2026-05-19
**影响**: Gatus 从集群访问 VPS 公网域名的探测连续失败约 4 小时；VPS 公网入口对自家出口 IP 执行 DROP，表现为 10s 超时。Tailscale TCP 检查仍成功，导致最初误判链路方向。
**发现人**: 用户反馈 Gatus 从 04:39 开始无法通过 VPS 检测网站连通性。

## 问题

VPS 上的 CrowdSec AppSec 将自家出口 IP 对 Jellyfin 播放进度接口的请求误判为 `crowdsecurity/crowdsec-appsec-outofband`，集群 LAPI 根据 profile 生成 4h ban。VPS firewall bouncer 拉取 decision 后写入 iptables/ip6tables，导致来自该出口 IP 的公网入口请求被 DROP。

结果：

- Gatus 的 `subconverter` / `derp` 等公网域名检查超时。
- `vps-caddy` TCP 检查仍成功，因为它走 Tailscale Service，不走 VPS 公网入口。
- Caddy access log 中故障窗口内几乎看不到 Gatus 的公网域名请求，因为流量在 firewall 层被 DROP。

## 现象

Gatus 日志：

```text
04:36:21 group=vps endpoint=subconverter success=true
04:36:21 group=vps endpoint=derp success=true
04:37:30 group=vps endpoint=subconverter success=false duration=10.001s
04:37:31 group=vps endpoint=derp success=false duration=10.001s
04:39:30 alert triggered for endpoint=subconverter
04:39:31 alert triggered for endpoint=derp
08:37:21 group=vps endpoint=subconverter success=true
08:37:21 group=vps endpoint=derp success=true
```

`vps-caddy` 检查同期成功：

```text
group=vps endpoint=vps-caddy success=true
```

CrowdSec alert：

```text
Reason: crowdsecurity/crowdsec-appsec-outofband
Machine: vps-cc
Scope:Value: Ip:<HOME_EGRESS_IP>
target_host: <JELLYFIN_DOMAIN>:443
target_uri: /Sessions/Playing/Progress
rule_ids: [901340 932370 949110 980170]
Begin: 04:35:32
End: 04:36:32
```

验证被 ban 的 IP 与 Gatus 到 VPS Caddy 的源 IP 相同：

```text
alert_ip_hash=<HASH>
latest_gatus_client_ip_hash=<HASH>
MATCH
```

## 根因

技术根因：

1. VPS Caddy 将请求送到本机 `crowdsec-agent:7422` 做 AppSec 检测。
2. AppSec CRS 对 Jellyfin `/Sessions/Playing/Progress` 误判，触发 `932370` 等规则并累计 anomaly。
3. `crowdsecurity/crowdsec-appsec-outofband` 生成 remediation alert。
4. 集群 LAPI 的 profile 对 remediation IP alert 生成 4h `ban` decision。
5. VPS firewall bouncer 将 decision 写入 `INPUT` / `FORWARD` / `DOCKER-USER`，`deny_action: DROP`。
6. Gatus 访问 VPS 公网域名时来自同一出口 IP，因此被 DROP，表现为 10s timeout。

排查过程根因：

1. 最初把用户给出的 `appsec component not authenticated: 401 Unauthorized` 当成主线，误以为请求死在 Caddy AppSec 阶段。
2. 没有先区分 Gatus 的不同探测路径：
   - `vps-caddy` 走 `tcp://ts-node-vps.network.svc:443`。
   - `subconverter` / `derp` 走公网域名。
3. 使用通用国外 IP 回显服务判断出口，受代理/分流影响，得到错误出口；后来改用国内回显和 Caddy access log 才确认真实路径源 IP。
4. 过早检查 VPS 到集群 Envoy/Tailscale 链路；这条链路不是本次 Gatus 公网探测失败的主路径。

## 修复

已执行：

1. 在 VPS CrowdSec agent 添加本地 AppSec config：

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

2. 在 VPS acquisition 中加载：

   ```yaml
   appsec_configs:
     - crowdsecurity/appsec-default
     - crowdsecurity/crs
     - local/jellyfin-exclusions
   ```

3. 在 VPS compose 中挂载到：

   ```text
   /etc/crowdsec/appsec-configs/jellyfin-exclusions.yaml
   ```

4. 同步并重建 `crowdsec-agent`。

5. 验证：

   ```text
   local/jellyfin-exclusions enabled,local
   loading /etc/crowdsec/appsec-configs/jellyfin-exclusions.yaml
   Appsec listening on 0.0.0.0:7422
   ```

6. Gatus 后续恢复：

   ```text
   group=vps endpoint=subconverter success=true
   group=vps endpoint=derp success=true
   group=vps endpoint=vps-caddy success=true
   ```

## 预防

1. Gatus 报 VPS 相关故障时，先按探测方式分组：

   ```text
   tcp://ts-node-vps.network.svc:443  -> Tailscale 路径
   https://<SUBDOMAIN>.<DOMAIN>       -> VPS 公网入口路径
   ```

2. 如果公网域名检查 10s timeout，但 Tailscale TCP 检查成功，优先查 VPS firewall bouncer / CrowdSec decision，不先查 Envoy/Tailscale。

3. 判断出口 IP 时，不只用单个外网回显服务。至少对比：

   ```text
   国内回显服务
   代理出口回显服务
   VPS Caddy access log 看到的 client_ip
   ```

4. `DROP` 类封禁没有 HTTP 状态码，Caddy access log 可能缺失请求；不要因为 Caddy 没日志就断言请求没发出。

5. AppSec 误判修复优先用精确排除：

   ```text
   特定 host / URI / rule ID
   ```

   避免优先使用：

   ```text
   全局 allowlist 自家出口 IP
   全局关闭 CRS
   全局关闭 appsec-outofband ban
   ```

6. 修改 compose 配置时，`task compose:sync:vps` 超时/中断后必须检查本地临时敏感文件是否残留：

   ```bash
   test -f compose/vps/.env && echo 'WARN .env exists' || echo '.env absent'
   ```

7. `appsec component not authenticated: 401 Unauthorized` 与 AppSec 误判 ban 是两类问题：

   - 401：Caddy 调 AppSec 时，AppSec 对 bouncer API key 校验失败或校验 LAPI 超时。
   - ban：AppSec/agent 已生成 alert，LAPI 生成 decision，bouncer 执行 DROP。

   排查时不要混为一谈。
