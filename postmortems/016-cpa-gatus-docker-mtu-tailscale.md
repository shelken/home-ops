# CPA 外部探测经 Docker→Tailscale 间歇 TLS 超时

**日期**: 2026-07-22  
**影响**: Gatus `cli-proxy-api-app-external` 约每 10–12 分钟 critical 告警；CPA 应用本身可用，公网用户偶发首连变慢/超时  
**发现人**: shelken / 调查会话  

## 问题

Gatus 外部探测 `https://cpa.<domain>/v1`（期望 404）规律失败：约每 12 分钟一次，错误为 `Client.Timeout exceeded while awaiting headers`（10s）。其它 external 端点（auth / jellyfin / echo 等）基本无此规律。

## 现象

```bash
# Gatus API：约 12 分钟一次 UNHEALTHY，错误 awaiting headers 10s
# VPS Caddy access.log：失败请求 duration≈10s，error=context canceled，UA=Gatus/1.0

# 失败窗口上游抓包（Caddy 容器 → 192.168.69.45 via tailscale0）
# 失败 SYN: mss 1460 → TLS 证书飞行前部 SACK 空洞 → 握手卡死
# 成功 SYN: mss ≈1240 → 正常 404

# 容器内复现（修前）
nsenter -t $(docker inspect -f '{{.State.Pid}}' caddy) -n ip route flush cache
nsenter -t ... -n curl --resolve cpa.<domain>:443:192.168.69.45 https://cpa.<domain>/v1
# → SSL connection timeout

# 容器内临时 MTU 对照（修前）
# 目标 1500 / 1400 → 超时；目标 1280 → 404 成功
```

路径（抓包确认）：

```text
Gatus → VPS 公网 Caddy → Tailscale → 192.168.69.45 (envoy https-cpa) → CPA
```

## 根因

**MTU 不统一，不是「要夹 MSS」。**

```text
MTU（因） ──决定──► TCP MSS（果，抓包读数）
```

| 口 | MTU | 说明 |
|---|---|---|
| eth0 | 1400 | ansible `interface_mtu`（公网腿，见 014） |
| tailscale0 | 1280 | Tailscale 默认；到 `192.168.69.45` 的**内层**下一跳 |
| Docker `homelab` / 容器 eth0 | **1500** | **缺口**：冷启动按 1500 切段 |

要点：

1. 到 `192.168.69.45` 的主机路由是 **`dev tailscale0`**，不是 eth0。eth0=1400 只约束 WireGuard **外层**，管不了容器内层 TCP 段长。  
2. 容器内核用 **PMTU 缓存**记住路径 MTU=1280（约 `mtu_expires=600s`）；过期后按容器 1500 拨号 → 内层超过 1280 → 大段丢失 → TLS 握手卡死。  
3. 抓包 mss=1460/1240 只表示「当时按哪份 MTU 拨」，**不是**独立修法旋钮。  
4. **为何主要 CPA 告警**：CPA 走独立上游且曾加 `keepalive off`（每次新拨），冷窗口必暴露；默认服务热池可复用或同秒 relearn 后再拨成功。

### 错误假设（调查中跑偏）

| 错误假设 | 实际 |
|---|---|
| Gatus 直连集群 LB / 家宽 IPv6 | 对端是 VPS 公网；Gatus netns 抓包确认 |
| 家宽 NAT 静默老化客户端连接 | 失败时请求已到 Caddy 并被 ACK |
| 上游 `keepalive off` 可修 | 加重冷拨，不治本 |
| Caddy `idle_timeout` 可修 | 当前 Caddy 版本不识别该 servers 选项，**直接起不来** |
| 主修 TCPMSS clamp | 与项目 014 后「统一 MTU」约定相悖；本问题应对齐 Docker 网 MTU |

同族：`014-vps-mss-blackhole-after-migration.md`（公网腿 eth0）；本次是 **Docker→Tailscale 内层腿**。

## 修复

1. **声明式**：`compose/vps/docker-compose.yml` 中 `homelab` 网络：

   ```yaml
   driver_opts:
     com.docker.network.driver.mtu: "1280"
   ```

2. **生效**：已有 network 不会热更新 MTU → `compose down` → 删 `homelab` → `up -d`（或等价重建）。  
3. **验证**：  
   - `docker network inspect homelab` → mtu 1280  
   - 容器内 `ip route flush cache` 后拨上游 → 404 亚秒（修前必超时）  
   - 冷启动 SYN mss≈1240  
4. **回退误改**：去掉无效 `idle_timeout`；`keepalive off` 对根因无效，建议与默认上游一致后删掉。  

## 预防

- **统一 MTU，不夹 MSS 当长期方案。** 公网腿用 `interface_mtu`；Docker→Tailscale 腿用 compose `driver.mtu` 与 `tailscale0` 对齐。  
- 排障「TCP 通、TLS handshake 卡」：先画清 **下一跳是 eth0 还是 tailscale0**，再比各口 MTU；抓包看 SYN mss 只作读数。  
- 改 Docker 网络 MTU 必须 **重建 network**；只 `compose up` 不会改已有 bridge 的 mtu。  
- Caddyfile 全局选项上线前用 `caddy adapt` / 同版本镜像校验；未知 `servers` 字段会导致整站起不来。  
- 对「只某一 upstream 规律超时」：查是否独立 transport / 每次新拨，是否更容易踩 PMTU 过期。  
- Tailscale **无** tailnet 级全局 MTU；不要指望 Admin 统一改 MTU 解决容器 1500。  
- 详细时间线与实验：`DISCOVERY.md`；Issue：#1310  

参考：

- RFC 2923 Path MTU Discovery 问题  
- `postmortems/014-vps-mss-blackhole-after-migration.md`  
- Tailscale 默认 MTU 1280；无 Admin 全局 MTU（[FR #16017](https://github.com/tailscale/tailscale/issues/16017)）
