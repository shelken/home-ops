# Kopia 备份部署设计方案

## 概述

在 compose-migrate 基础上完成 Kopia 备份部署，实现 sakamoto 和 VPS 数据的自动化备份到 189 云盘。

## 架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Kopia 统一仓库                               │
│                    S3: openlist / bucket: kopia                      │
│                         prefix: main/                                │
├─────────────────────────────────────────────────────────────────────┤
│  shelken@sakamoto:/backup/minio    ──┐                              │
│  shelken@sakamoto:/backup/compose  ──┼── 通过 hostname/username      │
│  shelken@vps:/backup/data          ──┘    自动隔离                   │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
              ┌───────────────┴───────────────┐
              │                               │
     ┌────────┴────────┐             ┌────────┴────────┐
     │    sakamoto     │             │       VPS       │
     │  ┌──────────┐   │             │  ┌──────────┐   │
     │  │  kopia   │───┼─────────────┼──│  kopia   │   │
     │  └──────────┘   │             │  └──────────┘   │
     │       │         │             │       │         │
     │       ▼         │             │       ▼         │
     │ K8s OpenList    │             │ 本地 OpenList   │
     │ (集群内)        │             │ (docker)       │
     └─────────────────┘             └─────────────────┘
              │                               │
              └───────────────┬───────────────┘
                              ▼
                      189 云盘 (20T)
```

### 关键设计决策

- 两个 kopia 实例连接同一个仓库（相同的 S3 bucket + prefix）
- 通过不同的 `hostname`（sakamoto / vps）+ 统一 `username`（shelken）区分数据
- VPS 需要新增 OpenList 容器作为 S3 代理层
- 完全声明式配置，无需手动初始化

---

## VPS 新增服务

### OpenList 服务

```yaml
# ==================== OpenList ====================
openlist:
  image: ghcr.io/openlistteam/openlist-git:v4.1.8
  container_name: openlist
  networks:
    - homelab
  restart: always
  labels:
    - homepage.group=VPS
    - homepage.name=openlist
    - homepage.icon=openlist.svg
    - homepage.description=网盘S3服务
  environment:
    TZ: Asia/Shanghai
    S3_ENABLE: "true"
    S3_PORT: "5246"
    HTTP_PORT: "80"
  volumes:
    - "${DATA_BASE_DIR}/openlist/data:/opt/openlist/data"
  ports:
    - "${DEPLOY_HOST}:5244:80/tcp"
    - "${DEPLOY_HOST}:5246:5246/tcp"
  deploy:
    replicas: 1
```

### VPS Kopia 服务

```yaml
# ==================== Kopia Backup ====================
kopia:
  image: kopia/kopia:0.22.3
  container_name: kopia
  hostname: vps
  networks:
    - homelab
  restart: always
  labels:
    - homepage.group=VPS
    - homepage.name=kopia
    - homepage.icon=kopia.svg
    - homepage.description=备份服务
  entrypoint: ["/bin/sh", "-c"]
  command:
    - |
      kopia repository connect from-config --file /app/config/repository.config --override-hostname=vps --override-username=shelken || \
      kopia repository create from-config --file /app/config/repository.config
      kopia policy import --from-file /app/config/policy.json
      exec kopia server start --address=0.0.0.0:51515 --server-username=$${KOPIA_SERVER_USERNAME} --server-password=$${KOPIA_SERVER_PASSWORD}
  environment:
    TZ: Asia/Shanghai
    KOPIA_PASSWORD: ${KOPIA_REPO_PASSWORD}
    KOPIA_SERVER_USERNAME: ${KOPIA_SERVER_USERNAME}
    KOPIA_SERVER_PASSWORD: ${KOPIA_SERVER_PASSWORD}
  volumes:
    - ./kopia/repository.config:/app/config/repository.config:ro
    - ./kopia/policy.json:/app/config/policy.json:ro
    - ${DATA_BASE_DIR}/kopia/cache:/app/cache
    - ${DATA_BASE_DIR}/kopia/logs:/app/logs
    - ${DATA_BASE_DIR}:/data:ro
  ports:
    - "${DEPLOY_HOST}:51515:51515/tcp"
  deploy:
    replicas: 1
```

---

## Sakamoto Kopia 服务

```yaml
# ==================== Kopia Backup ====================
kopia:
  image: kopia/kopia:0.22.3
  container_name: kopia
  hostname: sakamoto
  networks:
    - homelab
  restart: always
  labels:
    - homepage.group=sakamoto
    - homepage.name=kopia
    - homepage.icon=kopia.svg
    - homepage.description=备份服务
  entrypoint: ["/bin/sh", "-c"]
  command:
    - |
      kopia repository connect from-config --file /app/config/repository.config --override-hostname=sakamoto --override-username=shelken || \
      kopia repository create from-config --file /app/config/repository.config
      kopia policy import --from-file /app/config/policy.json
      exec kopia server start --address=0.0.0.0:51515 --without-password
  environment:
    TZ: Asia/Shanghai
    KOPIA_PASSWORD: ${KOPIA_REPO_PASSWORD}
  volumes:
    - ./kopia/repository.config:/app/config/repository.config:ro
    - ./kopia/policy.json:/app/config/policy.json:ro
    - ${DOCKER_DATA_DIR}/kopia/cache:/app/cache
    - ${DOCKER_DATA_DIR}/kopia/logs:/app/logs
    - ${MINIO_DATA_DIR}:/backup/minio:ro
    - ${DOCKER_DATA_DIR}:/backup/compose:ro
  ports:
    - "51515:51515"
  deploy:
    replicas: 1
```

---

## 配置文件

### 统一 policy.json（两台机器相同）

```json
{
  "@sakamoto": {
    "retention": {
      "keepHourly": 24,
      "keepDaily": 7
    },
    "compression": {
      "compressorName": "zstd-fastest"
    }
  },
  "@vps": {
    "retention": {
      "keepHourly": 24,
      "keepDaily": 7
    },
    "compression": {
      "compressorName": "zstd-fastest"
    }
  },
  "shelken@sakamoto:/backup/minio": {
    "scheduling": { "intervalSeconds": 3600 }
  },
  "shelken@sakamoto:/backup/compose": {
    "scheduling": { "intervalSeconds": 3600 }
  },
  "shelken@vps:/backup/data": {
    "scheduling": { "intervalSeconds": 3600 }
  }
}
```

### Sakamoto repository.config.tpl

```json
{
  "storage": {
    "type": "s3",
    "config": {
      "bucket": "kopia",
      "prefix": "main/",
      "endpoint": "azure://shelken-homelab/compose-sakamoto/OPENLIST_S3_ENDPOINT",
      "accessKeyID": "azure://shelken-homelab/compose-sakamoto/OPENLIST_S3_ACCESS_KEY_ID",
      "secretAccessKey": "azure://shelken-homelab/compose-sakamoto/OPENLIST_S3_SECRET_ACCESS_KEY"
    }
  },
  "caching": {
    "cacheDirectory": "/app/cache",
    "maxCacheSize": 5242880000,
    "maxMetadataCacheSize": 5242880000,
    "maxListCacheDuration": 30
  }
}
```

### VPS repository.config.tpl

```json
{
  "storage": {
    "type": "s3",
    "config": {
      "bucket": "kopia",
      "prefix": "main/",
      "endpoint": "azure://shelken-homelab/compose-vps/OPENLIST_S3_ENDPOINT",
      "accessKeyID": "azure://shelken-homelab/compose-vps/OPENLIST_S3_ACCESS_KEY_ID",
      "secretAccessKey": "azure://shelken-homelab/compose-vps/OPENLIST_S3_SECRET_ACCESS_KEY"
    }
  },
  "caching": {
    "cacheDirectory": "/app/cache",
    "maxCacheSize": 5242880000,
    "maxMetadataCacheSize": 5242880000,
    "maxListCacheDuration": 30
  }
}
```

---

## .env.tpl 更新

### Sakamoto .env.tpl 新增

```bash
# Kopia
KOPIA_REPO_PASSWORD=azure://shelken-homelab/compose-sakamoto/KOPIA_REPO_PASSWORD
```

### VPS .env.tpl 新增

```bash
# Kopia
KOPIA_REPO_PASSWORD=azure://shelken-homelab/compose-vps/KOPIA_REPO_PASSWORD
KOPIA_SERVER_USERNAME=azure://shelken-homelab/compose-vps/KOPIA_SERVER_USERNAME
KOPIA_SERVER_PASSWORD=azure://shelken-homelab/compose-vps/KOPIA_SERVER_PASSWORD
```

---

## 文件结构

```
compose/
├── sakamoto/
│   ├── docker-compose.yml      # 启用 kopia 服务
│   ├── .env.tpl                # 新增 KOPIA_REPO_PASSWORD
│   └── kopia/
│       ├── repository.config.tpl  # S3 连接配置
│       └── policy.json            # 统一策略文件
└── vps/
    ├── docker-compose.yml      # 新增 openlist + kopia 服务
    ├── .env.tpl                # 新增 kopia 相关变量
    └── kopia/
        ├── repository.config.tpl  # S3 连接配置
        └── policy.json            # 统一策略文件（与 sakamoto 相同）
```

---

## 启动流程

Kopia 容器启动时自动执行：

1. 尝试连接现有仓库，失败则创建新仓库
2. 幂等导入策略（每次启动都会同步）
3. 启动 Kopia 服务器

无需手动初始化，完全声明式。

---

## 首次部署注意事项

- **VPS OpenList**: 首次需通过 WebUI 配置 189 云盘连接，配置会持久化
- **Azure KeyVault**: 需提前配置好相关密钥
