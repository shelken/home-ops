# ZTE F50 流量监控 Exporter 设计

## 概述

监控中兴 F50 随身 Wi-Fi 的月度流量，将数据暴露给 Prometheus。

## 背景

- **设备**: 中兴 F50 随身 Wi-Fi，地址 `192.168.10.1`，开启了 ADB
- **数据源**: 设备 Web 管理界面提供 HTTP API (`/goform/goform_get_cmd_process`)
- **需求**: 获取月度流量统计，集成到现有 Prometheus 监控体系

## 架构

```
┌─────────────┐     HTTP API      ┌──────────────────┐     scrape     ┌────────────┐
│   ZTE F50   │◄─────────────────►│ zte-mifi-exporter│◄───────────────│ Prometheus │
│192.168.10.1 │  /goform/...      │   (K8s Pod)      │  :9586/metrics │            │
└─────────────┘                   └──────────────────┘                └────────────┘
                                         ▲
                                         │ env: ZTE_PASSWORD
                                  ┌──────┴───────┐
                                  │ExternalSecret│
                                  │  (KeyVault)  │
                                  └──────────────┘
```

## 技术决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 数据获取方式 | Web API | 数据丰富准确，无需 ADB 连接 |
| 实现语言 | Go | 性能好，与现有项目一致 |
| 部署方式 | K8s (app-template) | 与现有服务模式一致 |
| 密钥管理 | External Secrets + Azure KeyVault | 与现有基础设施集成 |
| Prometheus 集成 | serviceMonitor | app-template 原生支持 |

## 暴露指标 (MVP)

```prometheus
# 月度统计 (bytes)
zte_mifi_monthly_tx_bytes_total{host="192.168.10.1"}
zte_mifi_monthly_rx_bytes_total{host="192.168.10.1"}

# Exporter 状态
zte_mifi_scrape_success{host="192.168.10.1"} 1
```

## 配置

### 环境变量

| 变量 | 必须 | 默认值 | 说明 |
|------|------|--------|------|
| `ZTE_HOST` | 是 | - | F50 地址，如 `192.168.10.1` |
| `ZTE_PASSWORD` | 是 | - | Web 登录密码 |
| `LISTEN_ADDR` | 否 | `:9586` | exporter 监听地址 |

## 文件清单

### containers 仓库

```
apps/zte-mifi-exporter/
├── main.go           # Go exporter 主程序
├── go.mod            # Go 模块定义
├── Dockerfile        # 构建镜像
└── docker-bake.hcl   # 构建配置
```

### home-ops 仓库

```
k8s/apps/common/zte-mifi-exporter/
├── ks.yaml                    # Flux Kustomization
└── app/
    ├── kustomization.yaml     # Kustomize 配置
    ├── helmrelease.yaml       # HelmRelease (app-template + serviceMonitor)
    └── externalsecret.yaml    # 密钥同步
```

### Azure KeyVault

- Key: `zte-mifi-exporter`
- 包含字段: `ZTE_PASSWORD`

## ZTE API 细节

### 认证流程

1. 获取 `rd0` 和 `rd1` 参数: `GET /goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version`
2. 密码编码: `Base64(SHA256(password))`
3. 登录: `POST /goform/goform_set_cmd_process` with `goformId=LOGIN`

### 数据获取

登录成功后调用:
```
GET /goform/goform_get_cmd_process?cmd=monthly_tx_bytes,monthly_rx_bytes,date_month&multi_data=1
```

返回 JSON:
```json
{
  "monthly_tx_bytes": "1234567890",
  "monthly_rx_bytes": "9876543210",
  "date_month": "12"
}
```

## 后续扩展

设计预留了扩展空间，后续可添加:
- 实时速率指标
- 信号强度指标
- 电池状态指标
- 连接设备数量
