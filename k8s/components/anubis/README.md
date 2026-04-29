# Anubis component

本组件把各服务里重复的 Anubis 配置抽成独立 `HelmRelease`。

参考来源：https://github.com/bjw-s-labs/home-ops/tree/main/kubernetes/components/anubis

## 参考仓库有、本仓库暂未引入的配置

| 配置 | 参考仓库写法 | 含义 | 本仓库现状 | 是否值得引入 |
|---|---|---|---|---|
| `POLICY_FNAME` | `/etc/anubis/policy.yaml` | 指定 Anubis policy 文件路径 | 未配置，使用默认策略 | 值得评估；可以把 API、Git、Docker client 等放行规则集中到 policy，减少 HTTPRoute 例外规则 |
| `OG_EXPIRY_TIME` | `24h` | Open Graph 预览缓存/有效期 | 未配置 | 可选；如果链接预览频繁访问受保护页面，可以引入 |
| `OG_PASSTHROUGH` | `true` | 允许 Open Graph 抓取透传到后端 | 未配置 | 谨慎；对公开分享友好，但会扩大绕过挑战的入口 |
| `ANUBIS_DIFFICULTY` | `${ANUBIS_DIFFICULTY:="4"}` | 难度可由应用级变量覆盖 | 固定 `DIFFICULTY: "4"` | 值得引入；不同服务风险不同，应该允许单服务调难度 |
| `ANUBIS_MEM_LIMIT` | `${ANUBIS_MEM_LIMIT:="256Mi"}` | 内存限制可由应用级变量覆盖 | 固定 `256Mi` | 一般；当前两个服务一致，等出现内存差异再引入 |
| liveness probe | `anubis --healthcheck` | kubelet 存活检查，异常时重启容器 | 未配置 | 值得引入；独立 HelmRelease 后健康检查更重要 |
| readiness probe | `anubis --healthcheck` | 就绪检查，避免未就绪时接流量 | 未配置 | 值得引入；可减少启动期 502 |
| `policy.yaml` ConfigMap | `configMaps.policy.data.policy.yaml` | 声明 bot/client/path 规则 | 未配置 | 值得评估；先从通用 allow 规则开始，不要照搬 Gitea 专用规则 |
| policy ConfigMap mount | 挂载到 `/etc/anubis` | 让 Anubis 读取自定义 policy | 未配置 | 如果引入 `POLICY_FNAME`，必须一起引入 |
| `serviceMonitor` | metrics endpoint `:9090`，`interval: 30s` | Prometheus 抓取 Anubis 指标 | 只暴露 metrics service port，未创建 ServiceMonitor | 值得引入；便于观察挑战量、拦截量、延迟 |
| `METRICS_BIND` 端口 | `:9090` | metrics 监听地址 | `:8924` | 不必跟随；端口号无语义，本仓库沿用现状即可 |
| Secret per-app ExternalSecret | `${APP}-anubis-key-secret` | 每个 Anubis 实例独立 Secret | 使用集群级替换变量 | 不建议照搬；本仓库已有 SOPS/Flux 替换链路，除非要 per-app key 隔离 |
| Git/Docker/Gitea RSS imports | `(data)/clients/git.yaml` 等 | 放行特定非浏览器客户端 | 未配置 | 只按服务需要引入；OpenList/Vaultwarden 未必需要这些规则 |
| `/api/.*` allow rule | `path_regex: ^/api/.*` | API 路径绕过挑战 | 当前在各服务 HTTPRoute 层放行不同路径 | 值得评估；放到 policy 更集中，但各服务 API 路径不完全一致 |

## 参考仓库环境变量说明

| 变量 | 参考值 | 含义 | 本仓库是否已有 |
|---|---|---|---|
| `BIND` | `:8080` | Anubis HTTP 监听地址 | 有，当前为 `:8923` |
| `DIFFICULTY` | `${ANUBIS_DIFFICULTY:="4"}` | PoW 难度 | 有，但固定 `4` |
| `ED25519_PRIVATE_KEY_HEX` | Secret 引用 | Cookie/签名密钥 | 有，通过 Flux 替换注入 |
| `METRICS_BIND` | `:9090` | metrics 监听地址 | 有，当前为 `:8924` |
| `OG_EXPIRY_TIME` | `24h` | Open Graph 预览过期时间 | 无 |
| `OG_PASSTHROUGH` | `true` | Open Graph 请求透传 | 无 |
| `POLICY_FNAME` | `/etc/anubis/policy.yaml` | policy 文件路径 | 无 |
| `SERVE_ROBOTS_TXT` | `true` | 由 Anubis 提供 robots.txt | 有 |
| `TARGET` | `${ANUBIS_TARGET}` | 代理目标后端 | 有 |

## policy 文件重点

参考仓库 `policy.yaml` 做三类事：

1. 导入内置客户端规则：Git、Docker client。
2. 导入应用相关 bot 规则：Gitea RSS feeds。
3. 明确允许 `/api/.*`，最后导入默认配置。

本仓库现在用 HTTPRoute 按应用放行路径，例如 OpenList 放行 `/api`、`/dav`、`/p`，Vaultwarden 放行 `/api`、`/identity`、`/icons`、`/images`。如果后续引入 policy，建议只先迁移通用规则和明确安全的 API 放行；不要直接搬 Gitea RSS / Git / Docker client 规则。
