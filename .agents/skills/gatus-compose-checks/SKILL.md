---
name: gatus-compose-checks
description: 从 home-ops 的 Docker Compose 服务补齐 Gatus outside 健康检查，并选择轻量、可从集群内验证的探测方式。Use when 用户要求对比 compose 与 Gatus、补充 outside endpoints、检查集群外 VPS/sakamoto 服务监控、或调整 Gatus health check 轻量化。
---

# Gatus Compose Checks

## Quick start

1. 读取现有 Gatus outside 配置：`k8s/infra/common/observability/gatus/app/resources/outside/*.yaml`
2. 读取目标 Compose 服务：`compose/vps/docker-compose.yml` 与 `compose/sakamoto/docker-compose.yml`
3. 对比服务、端口、Caddy 路由与 Compose `healthcheck`
4. 从集群内现有 Pod 测试端点连通性，再编辑对应 outside YAML
5. 校验 YAML 语法并运行 `kustomize build`

## Endpoint 选择原则

优先级从高到低：

1. Compose 自带 `healthcheck` 使用的 HTTP 路径
2. 服务官方健康检查端点（如 `/health`、`/ready`）
3. 标准协议轻量端点（如 Docker API `/_ping`、Registry `/v2/`）
4. HTTP `HEAD` 检查轻量静态页或 API
5. TCP、UDP 或 DNS 连通性探测

Gatus 仅判断服务活性，不替代 Prometheus 监控指标或日志采集，探测请求保持轻量

## 轻量化规则

- 优先使用 `HEAD` 代替 `GET`
- 不使用 Gatus 抓取 `/metrics`，指标采集由 Prometheus 负责，Gatus 采用 TCP 连通性探测
- Docker socket proxy 使用 `/_ping`，响应体积小且语义明确
- Docker Registry 使用 `/v2/`，优先 `HEAD` 请求
- DNS 服务使用实际 DNS 查询校验解析功能，不依赖 Web 状态页
- Kopia 无轻量健康接口时使用 `HEAD /` 确认 UI 服务存活
- 代理类服务无 HTTP 端点时采用 TCP 或 UDP 连通性探测

## VPS 访问路径

配置 VPS endpoint 前，先看 Tailscale proxy Service：

- `k8s/infra/common/network/tailscale/proxy/node-vps.yaml`

从集群内部访问 VPS 时，优先使用该 Service 暴露的 DNS 名称和端口，严禁使用本机 curl 代替集群内连通性

## 集群内验证

找已有带工具的 Running Pod，例如有 `wget`、`nc`、`nslookup` 的应用 Pod。

示例命令：

```bash
kubectl -n <namespace> exec <pod> -- wget --spider -S -T 5 <url>
kubectl -n <namespace> exec <pod> -- nc -zvw3 <host> <port>
kubectl -n <namespace> exec <pod> -- nslookup -port=<port> <query-name> <dns-server>
```

验证内容应覆盖：

- HTTP 状态码符合预期
- TCP 与 UDP 端口连通
- DNS 查询返回 `NOERROR`
- 目标路径不返回大体积响应体

## 编辑要求

- 仅修改对应 outside YAML，除非发现网络连通本身缺少端口或 Caddy 路由缺失
- 保持现有 anchor、group、alert 与 UI 布局风格
- `hide-hostname` 与 `hide-url` 沿用同组既有配置
- 公开文档或 Skill 中严禁出现真实域名、公网 IP、内网 IP、节点名或凭据

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

- 新增或调整的 endpoint 清单
- 每个 endpoint 选用的轻量检查方式
- 集群内实测结果
- 未验证项与潜在风险
