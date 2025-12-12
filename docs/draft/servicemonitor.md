# ServiceMonitor 排查报告

> 排查时间: 2025-12-11
> 排查范围: `k8s/apps/common` 目录下使用 `app-template` 的 HelmRelease

## 概述

共发现 33 个使用 app-template 的 HelmRelease，其中仅 1 个配置了 serviceMonitor。

## 已配置 serviceMonitor 的服务

| 服务 | 状态 |
|------|------|
| echo | ✅ 已配置 |

## 明确支持但未配置 serviceMonitor 的服务 (建议优先添加)

| 服务 | 说明 | Metrics 端口/路径 |
|------|------|-------------------|
| **immich-server** | 已声明 metrics 端口，启用了 `IMMICH_METRICS_INCLUDE: all` | 8081 |
| **vaultwarden** | anubis 组件暴露了 `METRICS_BIND: ":8924"` | 8924 |

### 配置示例

参考 pocket-id 的 serviceMonitor 配置：

```yaml
serviceMonitor:
  app:
    serviceName: <service-name>
    endpoints:
      - port: metrics
        scheme: http
        path: /metrics
        interval: 60s
        scrapeTimeout: 30s
```

## 可能支持 metrics 但需确认的服务

| 服务 | 说明 | 备注 |
|------|------|------|
| home-assistant | HA 可通过集成启用 prometheus metrics | 需在 HA 中启用 prometheus 集成 |
| frigate | 支持 prometheus metrics | 需配置启用 |
| jellyfin | 有社区插件支持 metrics | 需安装 Prometheus 插件 |
| n8n | 支持通过配置启用 metrics | 需设置 `N8N_METRICS=true` |
| shlink | 有 prometheus 插件可选 | 需确认是否启用 |
| qbittorrent | 需外部 exporter | 可考虑 qbittorrent-exporter |
| plex | 需外部 exporter | 可考虑 Tautulli 或 plex-exporter |
| mosquitto | 需外部 exporter | 可考虑 mosquitto-exporter |
| affine | 未知是否支持 | 需查阅文档 |
| memos | 未知是否支持 | 需查阅文档 |

## 不太需要 metrics 的服务 (工具类/简单应用)

- it-tools
- librespeed
- metatube
- slash
- homepage
- dozzle
- kite
- kromgo
- ollama (无原生 metrics 支持)
- ollama-web (open-webui)
- shlink-web
- icloudpd
- icache
- seafile / seafile-db
- openlist
- karakeep
- go2rtc (无原生 metrics 支持)

## 建议优先级

### 高优先级 (已暴露 metrics 端口，只需添加 serviceMonitor)

1. **immich-server** - 已有 metrics 端口 8081，配置即可
2. **vaultwarden** (anubis) - 已有 metrics 端口 8924

### 中优先级 (需要开启配置或确认支持)

3. **home-assistant** - 需启用 prometheus 集成
4. **frigate** - 需确认配置
5. **n8n** - 需启用 metrics 配置

## 完整服务列表

```
k8s/apps/common/
├── affine/app/helmrelease.yaml
├── caches/icache/helmrelease.yaml
├── dozzle/app/helmrelease.yaml
├── echo/app/helmrelease.yaml              ✅ 已配置
├── frigate/app/helmrelease.yaml
├── go2rtc/app/helmrelease.yaml
├── home-assistant/app/helmrelease.yaml
├── homepage/app/helmrelease.yaml
├── icloudpd/app/helmrelease.yaml
├── immich/app/helmrelease.yaml            ⚠️ 需配置
├── immich/machine-learning/helmrelease.yaml
├── immich/microservices/helmrelease.yaml
├── it-tools/app/helmrelease.yaml
├── jellyfin/app/helmrelease.yaml
├── karakeep/app/helmrelease.yaml
├── kite/app/helmrelease.yaml
├── kromgo/app/helmrelease.yaml
├── librespeed/app/helmrelease.yaml
├── memos/app/helmrelease.yaml
├── metatube/app/helmrelease.yaml
├── mosquitto/app/helmrelease.yaml
├── n8n/app/helmrelease.yaml
├── new-api/app/helmrelease.yaml
├── ollama/app/helmrelease.yaml
├── ollama/web/helmrelease.yaml
├── openlist/app/helmrelease.yaml
├── plex/app/helmrelease.yaml
├── qbittorrent/app/helmrelease.yaml
├── seafile/app/helmrelease.yaml
├── seafile/db/helmrelease.yaml
├── shlink/app/helmrelease.yaml
├── shlink/web/helmrelease.yaml
├── slash/app/helmrelease.yaml
└── vaultwarden/app/helmrelease.yaml       ⚠️ 需配置
```
