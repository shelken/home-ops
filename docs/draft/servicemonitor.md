# ServiceMonitor 排查报告

> 排查时间: 2025-12-11
> 排查范围: `k8s/apps/common` 目录下使用 `app-template` 的 HelmRelease
> 注：高优先级的 `immich-server` 与 `vaultwarden` (anubis) metrics 现已配置落地

## 概述

通过以下命令获取当前使用 `app-template` 且未声明 `serviceMonitor` 的服务清单：

```bash
find k8s/apps/common -name "helmrelease.yaml" | xargs grep -l "app-template" | xargs grep -L "serviceMonitor"
```

## 已配置 serviceMonitor 的服务

| 服务 | 状态 |
|------|------|
| echo | ✅ 已配置 |

## 明确支持但未配置 serviceMonitor 的服务 (建议优先添加)

| 服务 | 说明 | Metrics 端口/路径 |
|------|------|-------------------|
| ~~**immich-server**~~ | 已在 `k8s/apps/common/immich/` 落地配置 | 8081 |
| ~~**vaultwarden**~~ | 已在 `k8s/components/anubis/helmrelease.yaml` 落地配置 | 8924 |

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
