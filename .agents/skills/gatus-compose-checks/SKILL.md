---
name: gatus-compose-checks
description: 从 home-ops 的 Docker Compose 服务补齐 Gatus outside 健康检查，并选择轻量、可从集群内验证的探测方式。Use when 用户要求对比 compose 与 Gatus、补充 outside endpoints、检查集群外 VPS/sakamoto 服务监控、或调整 Gatus health check 轻量化。
---

# Gatus Compose Checks

## Quick start

1. 读现有 Gatus outside 配置：
   - `k8s/infra/common/observability/gatus/app/resources/outside/*.yaml`
2. 读目标 compose：
   - `compose/vps/docker-compose.yml`
   - `compose/sakamoto/docker-compose.yml`
3. 对比服务、端口、Caddy routes、compose `healthcheck`。
4. 从集群内现有 Pod 测连通性，再编辑对应 outside YAML。
5. 校验 YAML 与 `kustomize build`。

## Endpoint 选择原则

优先级从高到低：

1. compose 自带 `healthcheck` 使用的 HTTP 路径。
2. 服务官方 health/status endpoint。
3. 协议标准轻量 endpoint，例如 Docker API `/_ping`、Registry `/v2/`。
4. HTTP `HEAD` 到轻量页面或 API。
5. TCP / UDP / DNS 连通性检查。

不要为了“看起来更完整”拉大响应。Gatus 只判断服务活性，不替代 Prometheus 或日志系统。

## 轻量化规则

- 能用 `HEAD` 就不要用 `GET`。
- 不用 Gatus 拉 `/metrics`；metrics 交给 Prometheus，Gatus 用 TCP connect。
- Docker socket proxy 用 `/_ping`，响应小且语义明确。
- Docker Registry 用 `/v2/`，优先 `HEAD`。
- DNS 服务用 DNS 查询验证真实功能，不用网页状态页。
- Kopia 无公开轻量 health 时，用 `HEAD /` 判断 UI 服务活着。
- 代理类服务无 HTTP health 时，用 TCP 或 UDP connect。

## VPS 访问路径

配置 VPS endpoint 前，先看 Tailscale proxy Service：

- `k8s/infra/common/network/tailscale/proxy/node-vps.yaml`

从集群视角访问 VPS，优先使用该 Service 暴露的 DNS 名称和端口。不要用本机 curl 结果代替集群内连通性。

## 集群内验证

找已有带工具的 Running Pod，例如有 `wget`、`nc`、`nslookup` 的应用 Pod。

示例命令：

```bash
kubectl -n <namespace> exec <pod> -- wget --spider -S -T 5 <url>
kubectl -n <namespace> exec <pod> -- nc -zvw3 <host> <port>
kubectl -n <namespace> exec <pod> -- nslookup -port=<port> <query-name> <dns-server>
```

验证内容应覆盖：

- HTTP 状态码是否符合配置。
- TCP/UDP 端口是否通。
- DNS 查询是否返回 `NOERROR`。
- 目标路径是否不会返回大 body。

## 编辑要求

- 只改对应 outside YAML，除非发现访问路径本身缺端口或 Caddy route 缺失。
- 保持现有 anchor、group、alert、ui 风格。
- `hide-hostname` / `hide-url` 按同组现有配置沿用。
- 不在公开文档或 skill 中写真实域名、IP、节点名、用户名或私有路径。

## 验证

编辑后至少执行：

```bash
python3 - <<'PY'
import yaml
for path in [
  'k8s/infra/common/observability/gatus/app/resources/outside/vps.yaml',
  'k8s/infra/common/observability/gatus/app/resources/outside/sakamoto.yaml',
]:
    yaml.safe_load(open(path))
    print('OK', path)
PY

kustomize build k8s/infra/common/observability/gatus/app >/tmp/gatus-app.yaml
```

最后汇报：

- 新增/调整了哪些 endpoint。
- 每个 endpoint 使用什么轻量检查方式。
- 集群内实测结果。
- 未验证项与风险。
