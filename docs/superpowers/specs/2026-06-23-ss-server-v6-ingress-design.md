# Shadowsocks v6 入口服务设计

## 背景

当前集群已有两个外部入口：
- **v4 入口**：`Loon → v4 → VPS(hysteria2) → Tailscale → envoy-external → 服务`
- **v6 入口**：`Loon → v6 → caddy-external → envoy-external → 服务`

两个入口最终都打到 `envoy-external`，访问的是公网域名。需要一个新的入口：通过 v6 直连集群，走 SS 协议，最终访问内网域名（由 `envoy-internal` 解析）。

## 本次范围

包含：
- 在集群部署 shadowsocks-rust server。
- 使用 multus-ipv6 分配独立 v6 地址。
- 端口 55483 TCP，method `2022-blake3-aes-256-gcm`。
- 密码通过 Azure KeyVault → ExternalSecret 注入。
- 以 `app-template` chart 部署，目录 `k8s/infra/common/network/external/ss-rust/`。
- 跟随已有外部入口（caddy-external）的 GitOps 流程。

不包含：
- UDP 支持（本次仅 TCP）。
- `sslocal` 或其他客户端组件。
- 监控/告警规则（后续按需添加）。
- 修改 envoy-external/envoy-internal/现有的 ss-subconverter。

## 架构

### 流量路径

```text
Loon (iOS)
  → v6 直连
  → Shadowsocks server (cluster, :55483)
  → 解密直出
  → CoreDNS 解析内网域名
  → envoy-internal (192.168.69.46)
  → HTTPRoute → 后端服务
```

### 组件

| 组件 | 说明 |
|------|------|
| shadowsocks-rust `ssserver` | 监听 55483 TCP，SS 2022 AEAD 解密后直接出站 |
| CoreDNS | 集群内建 DNS，内网域名解析到 envoy-internal |
| envoy-internal | 内网 Gateway，路由到对应服务 |

### 目录结构

```
k8s/infra/common/network/external/ss-rust/
├── ks.yaml                  # Flux Kustomization，被 external/ 引用
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml     # app-template chart
    └── externalsecret.yaml  # SS 密码
```

### HelmRelease 关键配置

- **Chart**: `bjw-s-labs/app-template`
- **Image**: `ghcr.io/shadowsocks/shadowsocks-rust`，固定版本 + digest
- **Multus**: 使用 `multus-ipv6` network（macvlan on eth1），分配 static IPv4（192.168.6.XX + MAC），v6 由 SLAAC 自动分配
- **Service**: 不需要 ClusterIP Service（四层透传，直用 multus 接口地址）
- **Probes**: TCP probe on 55483
- **Config**: JSON 格式配置文件挂载 ConfigMap，password 字段引用环境变量 `${SS_PASSWORD}`
- **密码**: Azure KeyVault → ExternalSecret → 容器环境变量 `SS_PASSWORD`
- **加密**: `2022-blake3-aes-256-gcm`，key 由 `ssservice genkey -m "2022-blake3-aes-256-gcm"` 生成

### 配置示例

```json
{
  "server": "::",
  "server_port": 55483,
  "method": "2022-blake3-aes-256-gcm",
  "password": "${SS_PASSWORD}",
  "mode": "tcp_only",
  "fast_open": true
}
```

ssserver 绑定 `::`（双栈），Loon 通过 SLAAC 分配的 v6 地址直连。

### Multus 地址分配

分配方式沿用 caddy-external：static IPv4 + 随机 MAC。IPv4 用于集群内 debug/管理，v6（SLAAC 自动分配）供 Loon 公网直连。

```yaml
k8s.v1.cni.cncf.io/networks: |
  [{
    "name": "multus-ipv6",
    "namespace": "network",
    "interface": "eth1",
    "ips": ["192.168.6.<XX>/24"],
    "mac": "02:<RANDOM>"
  }]
```

## 密钥管理

1. 本地运行 `ssservice genkey -m "2022-blake3-aes-256-gcm"` 生成 32 字节 Base64 key。
2. 写入 Azure KeyVault `shelken-homelab`，key 名 `ss-rust`。
3. ExternalSecret 读取并注入到 Pod 环境变量 `SS_PASSWORD`。

## 依赖

- `multus` (network namespace)
- `azure-store` (ExternalSecret ClusterStore)
- Flux GitRepository `flux-system`

## 验证方式

- Pod 启动后，从外部（如 Loon）用 v6 地址 + 55483 + `2022-blake3-aes-256-gcm` 连接。
- 测试访问 `http://<内网域名>` 确认路由到服务。
