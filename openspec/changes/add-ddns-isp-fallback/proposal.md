# Change: DDNS ISP 智能回退

## Why

当前 caddy-external 的 DDNS 容器（cloudflare-ddns）自动检测本机 IPv6 地址并更新 DNS 记录。然而，不同运营商对 443 端口的策略不同：

- **联通网络**（IPv6 以 2408 开头）：443 端口正常开放，可直连
- **移动网络**（IPv6 非 2408 开头）：443 端口被运营商屏蔽，无法直连

当网络从联通切换到移动时，DDNS 会更新为无法使用的移动 IPv6 地址，导致外部访问失败。

## What Changes

- 保持使用 cloudflare-ddns 镜像
- 新增一个轻量级 sidecar 容器，提供本地 HTTP 端点返回正确的 IPv6 地址
- 将 cloudflare-ddns 的 `IP6_PROVIDER` 从外部 URL 改为指向本地 sidecar 的 URL
- sidecar 逻辑：
  - 检测本机 IPv6 地址
  - 若为 `2408:` 开头（联通）→ 返回自动检测的 IP
  - 若为其他前缀（移动等）→ 返回预定义的 VPS IPv6 地址（`MAIN_VPS_IP_V6`）
- 保持现有的 5 分钟更新周期和 cloudflare-ddns 的所有其他配置

## Impact

- Affected specs: `ddns-routing`（新增）
- Affected code:
  - `k8s/infra/common/network/external/caddy-external/app/helmrelease.yaml`
    - 新增 sidecar 容器（ip-selector）
    - 修改 ddns 容器的 `IP6_PROVIDER` 环境变量
- 需要使用现有 secret：`CLOUDFLARE_API_TOKEN`、`MAIN_VPS_IP_V6`（需要从 cluster-secret 引用）
