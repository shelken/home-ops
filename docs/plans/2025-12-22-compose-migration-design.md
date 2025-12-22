# Docker Compose 统一管理设计方案

## 概述

将 `shelken/homelab-compose` 项目合并到 `home-ops`，实现 docker-compose 配置的统一管理、自动化部署和数据备份。

### 管理范围

| 机器 | 用途 | 原配置位置 |
|------|------|-----------|
| sakamoto | Mac Mini M4，集群外独立服务 | homelab-compose/apps |
| vps (161) | VPS 服务器 | homelab-compose/vps/161 |

### 设计目标

1. **配置版本控制** - 所有配置在 git 中管理
2. **敏感数据处理** - 使用 `azure://` 占位符 + Azure KeyVault
3. **自动化部署** - 本地 Taskfile 命令触发部署
4. **数据备份** - Kopia 定时备份到 OpenList S3（189 云盘）

---

## 目录结构

```
home-ops/
├── k8s/                      # 现有 K8s 配置
├── compose/                  # 新增：docker-compose 配置
│   ├── sakamoto/
│   │   ├── docker-compose.yml
│   │   ├── .env.tpl          # 使用 azure:// 占位符
│   │   ├── configs/          # 应用配置文件
│   │   └── kopia/
│   │       ├── repository.json.tpl
│   │       └── policy.json
│   └── vps/
│       ├── docker-compose.yml
│       ├── .env.tpl
│       ├── configs/
│       └── kopia/
│           ├── repository.json.tpl
│           └── policy.json
├── scripts/
│   ├── azure-inject.sh       # 现有：密钥注入
│   └── compose-deploy.sh     # 新增：部署脚本
└── .taskfile/
    └── compose.yaml          # 新增：Taskfile 任务
```

---

## 配置管理

### 配置文件分类

| 类型 | 示例 | 处理方式 |
|------|------|----------|
| 非敏感配置 | `TZ=Asia/Shanghai` | 直接写在 `.env.tpl` |
| 敏感配置 | API Token、密码 | `azure://vault/secret` 占位符 |
| 应用配置 | Caddyfile、fluent-bit.conf | 放入 `configs/` 目录 |

### .env.tpl 示例

```bash
# 非敏感配置
TZ=Asia/Shanghai
MAIN_DOMAIN=example.com

# 敏感配置
CLOUDFLARE_API_TOKEN=azure://shelken-homelab/cloudflare-api-token
DUFS_PASSWORD=azure://shelken-homelab/dufs-password
```

### 密钥注入

复用现有的 `scripts/azure-inject.sh`，支持 `azure://vault/secret[/json_key]` 格式。

---

## 部署流程

### 流程图

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ 1. 渲染配置   │ ──▶ │ 2. 同步文件   │ ──▶ │ 3. 重启服务   │
│ azure-inject │     │ rsync        │     │ docker compose│
└──────────────┘     └──────────────┘     └──────────────┘
```

### Taskfile 命令

```bash
# 部署到 sakamoto
task compose:deploy:sakamoto

# 部署到 vps
task compose:deploy:vps

# 仅同步配置，不重启
task compose:sync:sakamoto

# 查看远程状态
task compose:status:sakamoto
```

### compose-deploy.sh 脚本

```bash
#!/bin/bash
set -eo pipefail

HOST=$1
COMPOSE_DIR=$2
LOCAL_DIR=$3

# 1. 渲染 .env.tpl → .env
./scripts/azure-inject.sh "$LOCAL_DIR/.env.tpl" > "$LOCAL_DIR/.env"

# 2. 渲染 kopia 配置
./scripts/azure-inject.sh "$LOCAL_DIR/kopia/repository.json.tpl" > "$LOCAL_DIR/kopia/repository.json"

# 3. 同步文件到目标机器
rsync -avz --delete \
  --exclude '.env.tpl' \
  --exclude 'repository.json.tpl' \
  "$LOCAL_DIR/" "$HOST:$COMPOSE_DIR/"

# 4. 远程执行 docker compose
ssh "$HOST" "cd $COMPOSE_DIR && docker compose pull && docker compose up -d"

# 5. 清理本地生成的敏感文件
rm -f "$LOCAL_DIR/.env" "$LOCAL_DIR/kopia/repository.json"
```

### 目标机器配置

```yaml
# .taskfile/compose.yaml
vars:
  SAKAMOTO_HOST: "sakamoto.lan"
  SAKAMOTO_COMPOSE_DIR: "/opt/compose"
  VPS_HOST: "vps161"
  VPS_COMPOSE_DIR: "/opt/compose"
```

---

## 数据备份方案

### 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        sakamoto                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │ MinIO 数据    │    │ 其他服务数据  │    │ Kopia        │   │
│  │ /data/minio  │───▶│ /data/xxx    │───▶│ (定时任务)    │   │
│  └──────────────┘    └──────────────┘    └──────┬───────┘   │
└─────────────────────────────────────────────────│───────────┘
                                                  │
                                                  ▼
┌─────────────────────────────────────────────────────────────┐
│  OpenList (K8s 集群内)                                       │
│  ┌──────────────┐    ┌──────────────┐                       │
│  │ S3 接口       │───▶│ 189 云盘     │  (20T 免费)           │
│  └──────────────┘    └──────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

### Kopia 配置

#### repository.json.tpl

```json
{
  "storage": {
    "type": "s3",
    "config": {
      "bucket": "backup",
      "endpoint": "openlist.example.com",
      "accessKeyID": "azure://shelken-homelab/openlist-s3-access-key",
      "secretAccessKey": "azure://shelken-homelab/openlist-s3-secret-key"
    }
  }
}
```

#### policy.json (sakamoto)

```json
{
  "(global)": {
    "retention": {
      "keepDaily": 7,
      "keepWeekly": 4,
      "keepMonthly": 3
    },
    "scheduling": {
      "intervalSeconds": 86400
    },
    "compression": {
      "compressorName": "zstd"
    }
  },
  "sakamoto@sakamoto:/backup/minio": {
    "scheduling": { "intervalSeconds": 86400 }
  },
  "sakamoto@sakamoto:/backup/compose": {
    "scheduling": { "intervalSeconds": 86400 }
  }
}
```

#### docker-compose.yml (sakamoto kopia 部分)

```yaml
services:
  kopia:
    image: kopia/kopia:latest
    container_name: kopia
    restart: always
    command:
      - server
      - start
      - --address=0.0.0.0:51515
      - --without-password
    environment:
      KOPIA_PASSWORD: azure://shelken-homelab/kopia-repo-password
    volumes:
      - ./kopia:/app/config:ro
      - /data/minio:/backup/minio:ro
      - /data/compose:/backup/compose:ro
```

### Kopia 初始化与策略导入

```bash
# 连接仓库（首次创建 / 后续连接）
docker exec kopia kopia repository connect from-config --file /app/config/repository.json || \
docker exec kopia kopia repository create from-config --file /app/config/repository.json

# 导入策略
docker exec kopia kopia policy import --from-file /app/config/policy.json
```

---

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| Azure 认证失败 | 脚本终止，提示 `az login` |
| SSH 连接失败 | 脚本终止，显示错误信息 |
| docker compose 失败 | 显示远程日志，不回滚（手动处理） |

## 安全考虑

- 生成的 `.env` 文件仅存在于部署过程中，完成后删除
- `.env` 和 `repository.json` 加入 `.gitignore`
- SSH 使用密钥认证

---

## 迁移步骤

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 创建目录结构 | 在 home-ops 中创建 `compose/sakamoto/` 和 `compose/vps/` |
| 2 | 迁移配置 | 从 homelab-compose 复制 docker-compose.yml 和配置文件 |
| 3 | 改造 .env | 将 .env 改为 .env.tpl，敏感值替换为 `azure://` 占位符 |
| 4 | 添加 Kopia | 在 docker-compose 中添加 kopia 服务，创建策略文件 |
| 5 | 创建 Taskfile | 添加 `.taskfile/compose.yaml` 定义部署命令 |
| 6 | 测试部署 | 分别测试 sakamoto 和 vps 的部署流程 |
| 7 | 配置 Kopia | 初始化仓库，导入策略，验证自动备份 |
| 8 | 归档原项目 | 将 homelab-compose 设为 archived |

## 原项目归档

```bash
# 更新 README
echo "This project has been archived. See https://github.com/shelken/home-ops/tree/main/compose" > README.md

# GitHub 设置为 archived
gh repo archive shelken/homelab-compose
```

## Renovate 配置

在 home-ops 的 `.renovaterc.json5` 中添加 compose 目录的镜像更新规则。
