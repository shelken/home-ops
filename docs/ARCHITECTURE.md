# 架构总览

> 本文件描述整个 homelab 的物理部署、服务分布、网络入口、
> 监控采集和备份链路。所有敏感信息已替换为占位符。

---

## 1. 物理部署

```mermaid
graph TB
    subgraph SAKAMOTO["sakamoto"]
        subgraph LIMA["Lima VM"]
            CP["k3s control-plane<br/>sakamoto-k8s"]
        end
    end

    subgraph PVE["PVE"]
        subgraph PVE_VM["homelab-1 VM"]
            WORKER["k3s worker"]
        end
    end

    VPS["VPS"]
```

## 2. 网络拓扑

```mermaid
graph LR
    Internet["互联网"]
    F50["F50<br/>ZTE MiFi<br/>192.168.10.1"]

    subgraph HOME["家庭内网"]
        Router["router-mine<br/>OpenWrt<br/>192.168.6.1"]
        TVBox["TVBox / HK1 Box<br/>OpenWrt + daed<br/>192.168.6.3"]

        subgraph VLAN6["VLAN 6 · 主内网<br/>192.168.6.0/24"]
            SAKAMOTO["sakamoto<br/>192.168.6.144"]
            PVE_NODE["PVE<br/>192.168.6.213"]
        end

        subgraph VLAN50["VLAN 50 · IoT<br/>192.168.50.0/24"]
            IOT["智能家居设备"]
        end
    end

    subgraph K8S["k3s 集群"]
        CP["sakamoto-k8s<br/>192.168.6.80"]
        WORKER["homelab-1<br/>192.168.6.110"]

        subgraph LBIPAM["Cilium LB IPAM<br/>192.168.69.0/24"]
            K8SGW["k8s-gateway<br/>192.168.69.41"]
            ENV_EXT["envoy-external<br/>192.168.69.45"]
            ENV_INT["envoy-internal<br/>192.168.69.46"]
        end
    end

    VPS["VPS<br/>Tailscale: 100.97.0.0/16"]

    Internet <--> F50
    F50 <--> Router
    TVBox -->|"default route"| Router
    SAKAMOTO -->|"default gateway"| TVBox
    CP -->|"default gateway"| TVBox
    WORKER -->|"default gateway"| TVBox
    Router <--> SAKAMOTO
    Router <--> PVE_NODE
    Router <-->|"eBGP"| CP
    Router <-->|"eBGP"| WORKER
    SAKAMOTO --- CP
    PVE_NODE --- WORKER
    CP <-->|"LAN"| WORKER
    IOT -->|"Multus"| CP
    VPS <-->|"Tailscale"| CP
```

### 连接方式

| 链路 | 方式 | 说明 |
|------|------|------|
| F50 ↔ 互联网 | WAN (移动数据) | F50 是 router-mine 的互联网出口 |
| router-mine ↔ F50 | LAN | router-mine 通过 F50 出网；F50 断线时 zte-mifi-healer 自动重连 |
| TVBox ↔ router-mine | LAN (VLAN 6) | TVBox 是旁路由；自身默认路由仍指向 router-mine |
| sakamoto ↔ router-mine | LAN (VLAN 6) | 192.168.6.0/24 |
| PVE ↔ router-mine | LAN (VLAN 6) | 192.168.6.0/24 |
| IoT 设备 ↔ router-mine | LAN (VLAN 50) | 192.168.50.0/24 |
| IoT 设备 → k3s pods | Multus CNI | VLAN 50 接入集群 |
| sakamoto-k8s ↔ homelab-1 | LAN (VLAN 6) | k3s 节点间通信 |
| router-mine ↔ k3s 节点 | eBGP | Cilium 向 router-mine 通告 PodCIDR 和 LoadBalancerIP |
| Cilium LB IPAM | 192.168.69.0/24 | k8s-gateway: 192.168.69.41；envoy-external: 192.168.69.45；envoy-internal: 192.168.69.46 |
| VPS ↔ sakamoto-k8s | Tailscale | 100.97.0.0/16，VPS 通过 Tailscale 直连集群 subnet router |

---

## 3. 服务分布

> 本节只列主要 Compose 服务，不是完整容器清单；辅助容器以实际 `docker-compose.yml` 为准。

```mermaid
graph TB
    subgraph K3S["k3s 集群 (Flux 编排)"]
        NODE_SAKA["sakamoto-k8s · control-plane"]
        NODE_H1["homelab-1 · worker"]
    end

    subgraph COMPOSE_SAKA["sakamoto · Docker Compose"]
        CD_SAKA["Caddy (内部代理)
MinIO (S3 存储)
Registry Mirrors × 4
Kopia + Kopia Local (备份)
Nvidia DLS"]
    end

    subgraph COMPOSE_VPS["VPS · Docker Compose"]
        CD_VPS["Caddy (公网入口 + TLS)
CrowdSec (WAF)
dnsmasq (本机 DNS)
mosdns (DNS)
Hysteria2 / Hysteria2 no-obfs / Xray (代理)
DERP (Tailscale 中继)
OpenList (S3 网关)
Kopia (备份源)
Fluent Bit (日志采集)
Docker Registry Proxy
sub-converter (订阅转换)"]
    end
```

---

## 4. 入口流量全景

### DNS 解析链

```
用户服务:  A *. → <VPS_IP>

内部 DNS:  CNAME homelab-external → homelab-dynamic
              ├── A: VPS IP（手动）
              └── AAAA: 集群 v6（DDNS，由集群内 caddy-external 更新）

ExternalDNS 自动管理各服务子域名的记录

VPS 本机 DNS:
  127.0.0.1 -> dnsmasq
               MAIN_DOMAIN -> k8s-gateway 192.168.69.41
               其他域名 -> 公网 DNS
```

### 流量路径

```mermaid
graph LR
    subgraph INTERNET["互联网"]
        Client["客户端"]
    end

    subgraph DNS["Cloudflare DNS"]
        DNS_A["A *. → <VPS_IP>"]
        DNS_AAAA["AAAA *. → 集群 v6
DDNS by caddy-external"]
    end

    subgraph ENTRY_VPS["v4 入口"]
        VPS_Caddy["VPS Caddy
TLS 终结 + CrowdSec AppSec"]
    end

    subgraph ENTRY_V6["v6 入口"]
        Caddy_External["caddy-external
集群内 DDNS 更新"]
    end

    subgraph TAILSCALE["Tailscale"]
        TS_Link["VPS ← Tailscale → 集群"]
    end

    subgraph CLUSTER["K3s 集群"]
        Envoy_External["envoy-external
LB: <ENVOY_EXT_IP>"]
        GeoIP["GeoIP 过滤
CN / HK + VPS IP"]
        HTTPRoute["HTTPRoute
→ 后端服务"]
    end

    Client --> DNS_A
    DNS_A --> VPS_Caddy
    VPS_Caddy --> TS_Link
    TS_Link --> Envoy_External

    Client --> DNS_AAAA
    DNS_AAAA --> Caddy_External
    Caddy_External --> Envoy_External

    Envoy_External --> GeoIP
    GeoIP --> HTTPRoute
```

### 内网入口与旁路由 DNS

```mermaid
graph LR
    subgraph LAN["家庭内网<br/>192.168.6.0/24"]
        Client["局域网设备"]
        TVBox["TVBox 旁路由<br/>daed"]
        Router["router-mine<br/>DHCP + 内网 DNS 权威"]
    end

    subgraph DNSPATH["DNS 分流"]
        DaeDNS["daed DNS routing<br/>dport(53) -> direct"]
        RouterDNS["router-mine DNS<br/>内网域名"]
        ForeignDNS["DoH over proxy<br/>国外域名"]
        CNDNS["国内 DNS<br/>国内域名"]
    end

    subgraph TS["Tailscale<br/>100.97.0.0/16"]
        TS_Client["Tailscale 客户端"]
        TS_Subnet["subnet router"]
    end

    subgraph K8S["k3s 集群"]
        OpenwrtDNS["openwrt-dns<br/>(External-DNS webhook)"]
        Envoy_Internal["envoy-internal"]
    end

    Client -->|"DNS"| TVBox
    TVBox --> DaeDNS
    DaeDNS --> RouterDNS
    DaeDNS --> ForeignDNS
    DaeDNS --> CNDNS
    OpenwrtDNS -->|"同步 DNS 记录"| RouterDNS
    RouterDNS -->|"A/CNAME → LB IP"| Envoy_Internal
    TS_Client --> TS_Subnet
    TS_Subnet --> Envoy_Internal
```

### 入口一览

| # | 入口 | 协议 | DNS 链 | 终点 | 状态 |
|---|------|------|--------|------|------|
| 1 | VPS Caddy (v4) | 公网 | A `*` → VPS → Tailscale | envoy-external | ✅ 活跃 |
| 2 | caddy-external (v6) | 公网 | AAAA `*` → 集群 v6 | envoy-external | ✅ 活跃 |
| 3 | envoy-internal | 内网 | 客户端 DNS → TVBox daed → router-mine DNS (openwrt-dns 同步) → LB | envoy-internal | ✅ 活跃 |
| 4 | Tailscale | 内网 | 直连 → subnet router | 集群服务 | ✅ 活跃 |
| ~5~ | Cloudflare Tunnel | — | — | — | ❌ 已停用 |
| ~6~ | NetBird | — | — | — | ❌ 已停用 |

---

## 5. VPS Caddy 路由

```mermaid
graph TB
    subgraph VPS["VPS"]
        Caddy["VPS Caddy（443）"]

        subgraph LOCAL["Docker 本地服务<br/>172.20.0.0/16"]
            mosdns["vdns → mosdns"]
            subconv["sub → sub-converter"]
            derp["derp → DERP"]
            dhp["dhp → registry-proxy"]
        end

        subgraph HOST["Host 网络模式"]
            hysteria2["hysteria2"]
            hysteria2_no_obfs["hysteria2-no-obfs<br/>daed 兼容入口"]
            xray["xray"]
        end
    end

    subgraph CLUSTER["集群"]
        Envoy["envoy-external"]
        Envoy_CPA["envoy-external（CPA SNI）"]
    end

    Caddy -->|"cpa"| Envoy_CPA
    Caddy -->|"*（默认）"| Envoy
    Caddy --> mosdns
```

| 域名 | 路由目标 | 说明 |
|------|---------|------|
| `*`（默认） | → Tailscale → envoy-external | 大部分服务 |
| `cpa` | → Tailscale → envoy-external（CPA SNI） | CPA 协议专用 |
| `sub` | → 本地 sub-converter | 订阅转换 |
| `derp` | → 本地 DERP | Tailscale 中继 |
| `dhp` | → 本地 registry-proxy | Docker 镜像代理 |
| `vdns` | → 本地 mosdns | DNS 服务 |

> hysteria2、hysteria2-no-obfs、xray、dnsmasq 不经过 Caddy，
> 直接使用宿主机端口；no-obfs Hysteria2 供 daed 客户端使用。

---

## 6. 监控与日志采集

```mermaid
graph LR
    subgraph VPS["VPS"]
        NE_VPS["node-exporter"]
        CADDY_VPS["Caddy metrics"]
        FB_VPS["Fluent Bit<br/>VPS Caddy 日志"]
    end

    subgraph SAKAMOTO["sakamoto"]
        CADDY_SAKA["Caddy metrics"]
    end

    subgraph TS_PROXY["Tailscale Proxy"]
        TS_SVC["ts-node-vps.network.svc"]
    end

    subgraph COLLECT["集群内收集"]
        Prometheus["Prometheus"]
        VL["VictoriaLogs"]
        Gatus["Gatus"]
        FB_K8S["Fluent Bit<br/>k8s 容器日志"]
    end

    NE_VPS --> TS_SVC
    CADDY_VPS --> TS_SVC
    TS_SVC --> Prometheus
    CADDY_SAKA --> Prometheus

    FB_VPS --> VL
    FB_K8S --> VL

    Gatus --> TS_SVC
    Gatus --> VPS_Public["VPS 公网 URL"]
```

### 采集目标

| 数据源 | 代理方式 | 采集方式 |
|--------|---------|---------|
| VPS node-exporter | ts-node-vps:9100 | Prometheus |
| VPS Caddy metrics | ts-node-vps:2019 | Prometheus |
| VPS Docker 状态 | ts-node-vps:2575 | Gatus / Homepage |
| sakamoto Caddy | sakamoto.lan:2019 | Prometheus |
| VPS Caddy 访问日志 | VPS Fluent Bit | VictoriaLogs |
| k8s 容器日志 | 集群 Fluent Bit | VictoriaLogs |

---

## 7. 备份链路

```mermaid
graph TB
    subgraph K8S["k3s 集群"]
        PVC["PVC (Longhorn)"]
        PG["PostgreSQL (CNPG)"]
        Volsync["Volsync"]
        Barman["Barman Cloud"]
        Cluster_OpenList["OpenList (集群 S3)"]
    end

    subgraph SAKA_BACKUP["sakamoto"]
        MinIO["MinIO (S3)<br/>:9000"]
        COMPOSE_Data["Compose 数据"]
        SAKA_Kopia["Kopia（云端）"]
        SAKA_Kopia_Local["Kopia（本地）"]
        USB_HDD["外接 USB HDD"]
    end

    subgraph VPS_BACKUP["VPS"]
        VPS_Data["服务数据"]
        VPS_Kopia["Kopia"]
        VPS_OpenList["OpenList (本地 S3)"]
    end

    Cloud["189 天翼云盘"]

    PVC --> Volsync
    PG --> Barman
    Volsync --> MinIO
    Barman --> MinIO

    MinIO --> SAKA_Kopia
    COMPOSE_Data --> SAKA_Kopia
    SAKA_Kopia --> Cluster_OpenList
    Cluster_OpenList --> Cloud

    MinIO --> SAKA_Kopia_Local
    COMPOSE_Data --> SAKA_Kopia_Local
    SAKA_Kopia_Local --> USB_HDD

    VPS_Data --> VPS_Kopia
    VPS_Kopia --> VPS_OpenList
    VPS_OpenList --> Cloud
```

### 备份配置

| 链路 | 备份源 | 存储后端 | 目标 | 调度 |
|------|--------|---------|------|------|
| k8s PVC | Longhorn 快照 | Volsync → MinIO (sakamoto S3) | 189 云盘 | 每小时 |
| PostgreSQL | CNPG 集群 | Barman → MinIO (sakamoto S3) | 189 云盘 | 按 WAL 归档 |
| sakamoto MinIO | MinIO 数据 | Kopia → OpenList (集群 S3) | 189 云盘 | 6 小时 |
| sakamoto Compose | Compose 数据 | Kopia → OpenList (集群 S3) | 189 云盘 | 1 小时 |
| sakamoto 本地 | 用户数据 | Kopia Local → 外接 USB HDD | 本地 | 12 小时 |
| VPS 服务数据 | VPS 数据 | Kopia → OpenList (VPS 本地 S3) | 189 云盘 | 4 小时 |

> Kopia 仓库配置通过 `.env.tpl` 从外部密钥管理注入，不提交到 Git。

---

## 8. Flux 部署链路

```mermaid
graph TB
    GIT["GitHub: shelken/home-ops (main)"]

    subgraph BOOT["flux bootstrap"]
        STAGING["k8s/clusters/staging/kustomization.yaml"]
        REPOS["repos.yaml<br/>flux-repositories"]
    end

    subgraph SOURCE["GitRepository: flux-system"]
        SRC_MONITOR["监听 main 分支变更, interval: 1m"]
    end

    subgraph INFRA_LAYER["infra.yml (Flux Kustomization)"]
        INFRA_CFG["path: ./k8s/infra/staging<br/>wait: true<br/>patches: sops + subst"]
    end

    subgraph APPS_LAYER["apps.yml (Flux Kustomization)"]
        APPS_CFG["path: ./k8s/apps/staging<br/>dependsOn: infra<br/>wait: false<br/>patches: sops + subst"]
    end

    subgraph KUSTOMIZE_INFRA["kustomize build -> 生成子级 Flux CRD"]
        IN_CAT["k8s/infra/staging/kustomization.yaml<br/>imports: ../common/{network, database}"]
        IN_CATEGORY["k8s/infra/common/{category}/kustomization.yaml"]
        IN_CHILD["category/ks.yaml<br/>(caddy-external, ss-rust)"]
        IN_CAT --> IN_CATEGORY --> IN_CHILD
    end

    subgraph KUSTOMIZE_APPS["kustomize build -> 生成子级 Flux CRD"]
        AP_CAT["k8s/apps/staging/kustomization.yaml<br/>imports: ../common/"]
        AP_LAYER["k8s/apps/common/kustomization.yaml"]
        AP_CHILD["app/ks.yaml<br/>(echo, homepage)"]
        AP_CAT --> AP_LAYER --> AP_CHILD
    end

    subgraph APP_DIR["app/ 目录 (kustomize)"]
        DIR_KS["kustomization.yaml<br/>resources: helmrelease, externalsecret"]
        DIR_HR["helmrelease.yaml<br/>app-template chart"]
        DIR_ES["externalsecret.yaml<br/>Azure KeyVault"]
    end

    subgraph CLUSTER["k3s 集群部署结果"]
        HELM["HelmRelease -> app-template<br/>Helm Chart (OCIRepository)"]
        OBJ["Secret / ConfigMap / Service<br/>chart template 生成"]
        POD["Pod"]
    end

    GIT -.->|创建| STAGING
    STAGING --> SOURCE
    OCI["OCIRepository<br/>app-template"]
    REPOS -.-> OCI

    SOURCE --> INFRA_LAYER
    SOURCE --> APPS_LAYER

    INFRA_LAYER --> IN_CAT
    APPS_LAYER --> AP_CAT

    IN_CHILD -.->|path: ./{app}/| APP_DIR
    AP_CHILD -.->|path: ./{app}/| APP_DIR

    DIR_HR --> HELM
    DIR_ES --> OBJ
    HELM --> POD
    HELM --> OBJ
```

### 部署顺序

| 层 | Kustomization | 入口 | 等待上游 | 说明 |
|---|-------------|------|---------|------|
| 0 | `flux-system` GitRepository | 由 bootstrap 创建 | — | 监听代码仓库，触发所有同步 |
| 1 | `flux-repositories` | `repos.yaml` → `k8s/clusters/common/repos/` | — | 预注册 Helm chart 源（app-template 等） |
| 2 | `infra` | `infra.yml` → `k8s/infra/staging/` | — | 基础设施先部署，`wait: true` |
| 3 | 各 infra 子 Kustomization | `k8s/infra/common/{category}/<app>/ks.yaml` | infra 层父级 | 网络、存储、数据库、监控等 |
| 4 | `apps` | `apps.yml` → `k8s/apps/staging/` | infra 完成 | 应用层后部署，`wait: false` |
| 5 | 各 apps 子 Kustomization | `k8s/apps/common/<app>/ks.yaml` | apps 层父级 | 普通业务应用 |

### 关键机制

- **变量注入**：所有子 Kustomization 自动获得 `cluster-secrets`（Secret）和 `cluster-settings`（ConfigMap）中的 postBuild 变量。可通过标签 `substitution.flux/disabled: "true"` 跳过。
- **SOPs 解密**：所有子 Kustomization 自动获得 SOPs age 解密能力。
- **等待策略**：`infra` 层 `wait: true`（等待所有子资源就绪），`apps` 层 `wait: false`（快速同步，不等待）。
- **HelmRelease**：最终通过 `app-template` chart（OCIRepository）或直接 Helm chart 部署 Pod。
