# CrowdSec 部署与运维指南

## 目标

记录 CrowdSec 的部署拓扑、代码位置、运行时约束、常用查询命令和常见故障排障入口，具体配置以代码为准

## 当前拓扑

```text
v4 公网请求 -> VPS Caddy -> VPS crowdsec-agent AppSec (:7422) -> 业务服务
v6 公网请求 -> 集群 caddy-external -> 集群 CrowdSec AppSec (:7422) -> Envoy Gateway -> 业务服务

VPS agent / 集群 AppSec -> 集群 CrowdSec LAPI -> PostgreSQL / profile / notification / decisions
```

- 集群运行 LAPI 和 v6 AppSec，不运行日志采集 agent
- VPS `crowdsec-agent` 采集 VPS Caddy 与 SSH 日志，并执行 v4 AppSec
- VPS `crowdsec-firewall-bouncer` 将 decisions 写入 VPS iptables 与 ip6tables
- 两侧 AppSec 仅启用虚拟补丁与通用探测规则，不启用 OWASP CRS

## 代码位置

- 集群 LAPI 与 v6 AppSec：[k8s/infra/common/security/crowdsec/app/helmrelease.yaml](../k8s/infra/common/security/crowdsec/app/helmrelease.yaml)
- 集群 v6 入口 Caddy：[k8s/infra/common/network/external/caddy-external/app/helmrelease.yaml](../k8s/infra/common/network/external/caddy-external/app/helmrelease.yaml)
- VPS agent、firewall bouncer 与 Caddy：`nix-config` 仓库 `hosts/vps/<VPS_HOST>/apps/` 下的 `crowdsec-agent/`、`crowdsec-firewall-bouncer/` 与 `caddy/`

## 运行时约束

- LAPI Service 类型为 LoadBalancer，供 VPS 侧访问，当前地址通过 `mise exec -- kubectl -n security get svc crowdsec-service -o wide` 查询
- VPS agent 禁用本地 LAPI，在 VPS 容器内执行 `cscli bouncers list` 会报错，查 bouncer、alerts 与 decisions 统一在集群 LAPI 执行
- VPS firewall bouncer 使用 `DROP` 动作并写入 `DOCKER-USER` 链，命中的请求表现为超时而非 403，且影响容器暴露端口
- VPS Caddyfile 由 NixOS 声明挂载，修改后需在 `nix-config` 重新部署重建容器，容器内 `caddy reload` 仍读取旧挂载
- VPS Caddy 访问日志写入 `/var/log/caddy/access.log`，不输出到 `docker logs caddy`
- VPS 机密由 `nix-config` 的 sops 模板生成 env 文件下发，集群机密由 ExternalSecret 管理

## 常用命令

### 集群 LAPI

- 查看组件状态与日志
  ```bash
  mise exec -- kubectl -n security get pods,svc,pvc | grep crowdsec
  mise exec -- kubectl -n security logs deploy/crowdsec-lapi --tail=200
  mise exec -- kubectl -n security describe helmrelease crowdsec
  ```
- 查看与手动解封 decisions
  ```bash
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions list
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions list --origin crowdsec
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions delete -i <IP>
  ```
- 查看 alerts 与 bouncers
  ```bash
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts list --since 6h
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts inspect <ALERT_ID> -d
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers list
  ```
- 查看集群 AppSec 已加载规则
  ```bash
  mise exec -- kubectl -n security exec -c crowdsec-appsec deploy/crowdsec-appsec -- cscli collections list
  mise exec -- kubectl -n security exec -c crowdsec-appsec deploy/crowdsec-appsec -- cscli appsec-configs list
  ```

### VPS 侧

- 查看服务与容器状态
  ```bash
  ssh <VPS_HOST> 'systemctl is-active docker-crowdsec-agent docker-crowdsec-firewall-bouncer docker-caddy'
  ssh <VPS_HOST> 'docker ps | grep -E "crowdsec|caddy"'
  ```
- 查看 agent 日志与已加载规则
  ```bash
  ssh <VPS_HOST> 'docker logs crowdsec-agent --since 30m'
  ssh <VPS_HOST> 'docker exec crowdsec-agent cscli collections list'
  ssh <VPS_HOST> 'docker exec crowdsec-agent cscli appsec-configs list'
  ```
- 查看 firewall bouncer 与规则链
  ```bash
  ssh <VPS_HOST> 'docker logs crowdsec-firewall-bouncer --since 30m'
  ssh <VPS_HOST> 'sudo iptables -S DOCKER-USER | head -80'
  ssh <VPS_HOST> 'sudo ip6tables -S DOCKER-USER | head -80'
  ```
- 查看 Caddy 访问日志
  ```bash
  ssh <VPS_HOST> 'tail -n 100 /var/log/caddy/access.log'
  ```

## 常见故障模式

- 公网检查超时但内网或 Tailscale TCP 检查成功 → 排查自家出口 IP 是否被 VPS firewall bouncer `DROP`，在集群 LAPI 查近 6 小时 alerts 与 decisions，并交叉核对出口 IP
  ```bash
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts list --since 6h
  mise exec -- kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions list -a | grep '<IP>'
  ```
- Caddy 报错 `appsec component not authenticated: 401 Unauthorized` → 排查 VPS `crowdsec-agent` 到集群 LAPI `HEAD /v1/decisions/stream` 的连通性与 API key，短暂出现多为 agent 重启窗口
  ```bash
  ssh <VPS_HOST> 'docker logs crowdsec-agent --since 10m | grep -Ei "unauthorized|invalid API key|Error checking auth|decisions/stream"'
  mise exec -- kubectl -n security logs deploy/crowdsec-lapi --since=10m | grep 'HEAD /v1/decisions/stream'
  ```
- 区分拦截来源 → 401 为 AppSec 鉴权失败，403 来自业务或 Caddy，429 来自限流，firewall ban 表现为超时且不一定留下 access log
- 误判自家出口 IP → 通过 `cscli alerts inspect <ALERT_ID> -d` 区分本地生成（`Kind: crowdsec`）与社区情报（`Source: CAPI`），确认出口 IP 时交叉比对国内回显、代理回显与 VPS Caddy access log 中的 `client_ip`

## 外部参考

- CrowdSec AppSec 配置语法：<https://docs.crowdsec.net/docs/next/appsec/configuration>
- CrowdSec AppSec hooks：<https://docs.crowdsec.net/docs/next/appsec/hooks.md>
- CrowdSec AppSec 自定义配置与测试：<https://docs.crowdsec.net/docs/next/appsec/configuration_creation_testing/>
- CrowdSec profiles：<https://docs.crowdsec.net/docs/next/profiles/format>
