# Anubis component

本组件把各服务里重复的 Anubis 配置抽成独立 `HelmRelease`。

参考来源：

- bjw-s-labs 组件：https://github.com/bjw-s-labs/home-ops/tree/main/kubernetes/components/anubis
- Anubis v1.25.0 默认 policy：https://github.com/TecharoHQ/anubis/blob/v1.25.0/data/meta/default-config.yaml

## 参考仓库有、本仓库已补齐的配置

| 配置 | 当前写法 | 含义 | 说明 |
|---|---|---|---|
| `POLICY_FNAME` | `/etc/anubis/policy.yaml` | 指定 Anubis policy 文件路径 | 已引入；让策略由 ConfigMap 管理 |
| `policy.yaml` ConfigMap | `configMaps.policy.data.policy.yaml` | 声明 bot/client/path 规则 | 已引入；不照搬 Gitea 专用规则 |
| policy 挂载 | `/etc/anubis` 只读挂载 | 让 Anubis 读取自定义 policy | 已引入 |
| `OG_EXPIRY_TIME` | `24h` | Open Graph 预览缓存/有效期 | 已引入，跟随参考仓库 |
| `OG_PASSTHROUGH` | `true` | 允许 Open Graph 抓取透传到后端 | 已引入；利于链接预览，但会扩大绕过挑战入口 |
| `ANUBIS_DIFFICULTY` | `${ANUBIS_DIFFICULTY:=4}` | 允许按应用覆盖 PoW 难度 | 已引入；默认仍是 4 |
| `ANUBIS_MEM_LIMIT` | `${ANUBIS_MEM_LIMIT:=256Mi}` | 允许按应用覆盖内存限制 | 已引入；默认仍是 256Mi |
| liveness probe | `anubis --healthcheck` | 异常时重启 Anubis | 已引入 |
| readiness probe | `anubis --healthcheck` | 未就绪时不接流量 | 已引入 |
| `serviceMonitor` | metrics endpoint `:8924`，`interval: 30s` | Prometheus 抓取 Anubis 指标 | 已引入；端口沿用本仓库现状 |
| reloader annotation | `reloader.stakater.com/auto: "true"` | policy/secret 变更后自动滚动 | 已引入 |

## 没有照搬的配置

| 参考配置 | 未照搬原因 |
|---|---|
| 独立 `${APP}-anubis` OCIRepository | 本仓库规范是直接引用 `flux-system/app-template` |
| 每应用 ExternalSecret | 本仓库已有 SOPS + Flux `substituteFrom` 注入 `ANUBIS_ED25519_PRIVATE_KEY_HEX` |
| `(data)/apps/gitea-rss-feeds.yaml` | Gitea 专用，本仓库当前 Anubis 保护对象不是 Gitea |
| `(data)/clients/git.yaml` | Git client 专用，OpenList/Vaultwarden 不需要 |
| `(data)/clients/docker-client.yaml` | Registry client 专用，OpenList/Vaultwarden 不需要 |
| 参考仓库 metrics 端口 `:9090` | 本仓库已有 `:8924`，端口号无业务语义 |

## 当前 policy

```yaml
bots:
  - import: (data)/common/allow-api-like.yaml
  - import: (data)/meta/default-config.yaml
```

### 与 Anubis 官方默认 policy 的差别

官方 v1.25.0 默认 policy 等价于只导入：

```yaml
bots:
  - import: (data)/meta/default-config.yaml
```

本仓库只额外加了一条：

| 额外规则 | 行为 | 原因 |
|---|---|---|
| `(data)/common/allow-api-like.yaml` | 放行 `path.startsWith("/api/")` 且方法不是 `GET`/`HEAD` 的请求 | 避免移动端、CLI、浏览器前端发起的 API 写请求被 PoW 挑战卡住 |

### 官方默认 policy 大致做什么

`(data)/meta/default-config.yaml` 主要包含：

| 类别 | 行为 |
|---|---|
| 病态 bot | 导入 `_deny-pathological.yaml` 和 aggressive Brazilian scrapers，直接拒绝明显恶意/异常爬虫 |
| AI/LLM bot | 默认使用 aggressive AI block，偏严格拦截训练/抓取类 bot |
| 正常搜索引擎 | 放行 Google、Apple、Bing、DuckDuckGo、Qwant、Internet Archive、Kagi、Marginalia、Mojeek 等 |
| Firefox AI preview | 对 `x-firefox-ai` 类请求加挑战 |
| 基础互联网路径 | 放行 `/.well-known`、favicon、robots.txt 等常见基础路径 |
| 高风险地区/ASN | 对 BR、CN、Cloudflare、Huawei Cloud、Alibaba Cloud 等增加权重；依赖 Thoth 订阅时才完整生效 |
| 通用浏览器 | 对 `Mozilla|Opera` User-Agent 加权，让正常浏览器进入挑战/判断流程 |

所以，本仓库当前策略 = 官方默认策略 + 非 GET/HEAD API 请求放行。没有引入 Git、Docker、Gitea RSS 这类应用专用白名单。
