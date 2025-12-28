# Design: DDNS ISP 智能回退

## Context

caddy-external 部署中有一个 cloudflare-ddns sidecar 容器，用于自动更新 DNS 记录。当网络环境发生变化（联通→移动）时，自动检测的 IPv6 地址可能指向一个 443 端口被屏蔽的网络，导致服务不可达。

需要一个低侵入性的解决方案，保持使用 cloudflare-ddns 镜像，同时增加 IP 选择逻辑。

## Goals / Non-Goals

### Goals
- 根据检测到的 IPv6 前缀智能选择 DNS 记录值
- 联通网络（2408: 前缀）使用自动检测的 IP
- 非联通网络使用固定的 VPS IPv6 地址
- 最小化对现有配置的改动
- 保持使用 cloudflare-ddns 镜像

### Non-Goals
- 不替换 cloudflare-ddns 镜像
- 不改变更新周期或其他 DDNS 行为
- 不处理 IPv4（当前已禁用）

## Decisions

### 方案选择：本地 HTTP Sidecar

**选定方案**：新增一个轻量级 sidecar 容器，提供 HTTP 端点返回正确的 IP。

**原因**：
1. cloudflare-ddns 支持 `IP6_PROVIDER=url:<URL>` 配置
2. sidecar 可以完全自定义 IP 选择逻辑
3. 对现有 cloudflare-ddns 配置改动最小（仅修改一个环境变量）
4. 使用 shell 脚本 + netcat/busybox httpd 即可实现，无需构建新镜像

**备选方案及排除原因**：
- `debug.const:` 固定 IP → 无法动态选择，排除
- 替换为自定义脚本容器 → 侵入性大，排除
- initContainer 写入配置文件 → cloudflare-ddns 不支持文件配置，排除

### Sidecar 实现

使用 `busybox` 镜像运行一个简单的 HTTP 服务器：

```yaml
containers:
  ip-selector:
    image:
      repository: busybox
      tag: stable
    command: ["/bin/sh", "-c"]
    args:
      - |
        while true; do
          # 检测当前 IPv6
          CURRENT_IP=$(wget -qO- https://6.ipw.cn 2>/dev/null)
          # 判断前缀
          if echo "$CURRENT_IP" | grep -q "^2408:"; then
            RESULT_IP="$CURRENT_IP"
          else
            RESULT_IP="$MAIN_VPS_IP_V6"
          fi
          # 写入文件供 HTTP 服务读取
          echo "$RESULT_IP" > /tmp/current-ip
          sleep 60
        done &
        # 启动简单 HTTP 服务
        while true; do
          echo -e "HTTP/1.1 200 OK\r\n\r\n$(cat /tmp/current-ip)" | nc -l -p 8888
        done
```

**端口**：8888（内部使用）

### cloudflare-ddns 配置修改

```yaml
IP6_PROVIDER: "url:http://localhost:8888"
```

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| sidecar 启动时 /tmp/current-ip 不存在 | 在 HTTP 循环前先执行一次 IP 检测 |
| 外部 IP 检测服务不可用 | 当检测失败时默认使用 VPS IP |
| busybox nc 的行为差异 | 使用 while 循环确保持续服务 |

## Open Questions

- 是否需要健康检查探针？（当前方案不需要，cloudflare-ddns 会自行重试）
