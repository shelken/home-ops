# Kopia 配置说明

## 文件结构

| 文件 | 说明 |
|------|------|
| `repository.config.tpl` | 存储库连接配置模板，使用 azure:// 占位符 |
| `policy.json` | 备份策略配置（VPS 通过符号链接共享此文件） |

## policy.json

Kopia 策略采用层级继承机制：

```
(global) → @hostname → user@hostname → user@hostname:/path
```

### 当前配置结构

| 策略目标 | 配置内容 | 说明 |
|---------|---------|------|
| `@sakamoto` | retention, compression, files.ignore | sakamoto 主机级别 |
| `@vps` | retention, compression, files.ignore | vps 主机级别 |
| `shelken@sakamoto:/backup/compose` | scheduling: 1小时 | compose 备份调度 |
| `shelken@sakamoto:/backup/minio` | scheduling: 6小时 | minio 备份调度 |
| `shelken@vps:/backup/data` | scheduling: 4小时 | VPS 数据备份调度 |

### 排除规则语法

- `cache` - 匹配任意位置的 cache 目录
- `/cache` - 仅匹配根目录下的 cache 目录
- `*.log` - 匹配所有 .log 文件

### 设计原则

- **统一策略**：retention 和 compression 在 @hostname 级别配置，所有路径继承
- **独立调度**：每个备份路径单独配置 scheduling，互不影响
- **幂等导入**：容器启动时执行 `kopia policy import`，自动覆盖更新
- **共享仓库**：sakamoto 和 VPS 使用相同的 Kopia 仓库（通过 189 云盘 + OpenList S3）

## 遇到的问题和修正

### 1. repository.config 只读挂载问题

**问题**：直接挂载 repository.config 为只读，Kopia 尝试修改时失败

**修正**：在 entrypoint 中复制配置到可写位置
```yaml
entrypoint: ["/bin/sh", "-c"]
command:
  - |
    cp /app/config/repository.config.tpl /app/repository.config
    kopia repository connect from-config --file /app/repository.config ...
```

### 2. Kopia Server 需要 --insecure 标志

**问题**：不加 `--insecure` 时，服务器会因 TLS 未配置而不稳定

**修正**：添加 `--insecure` 标志
```yaml
exec kopia server start --insecure --address=0.0.0.0:51515 ...
```

### 3. 环境变量在 shell command 中展开

**问题**：docker-compose 的 `${}` 会在 compose 解析时展开，而非运行时

**修正**：使用 `$${}` 进行转义，让变量在容器 shell 中展开
```yaml
--server-username=$${KOPIA_SERVER_USERNAME}
```

### 4. VPS 和 sakamoto 共享仓库密码

**问题**：两台机器使用不同的 Azure Key Vault secret，但需要相同的仓库密码

**修正**：VPS 的 .env.tpl 直接引用 sakamoto 的密码
```
KOPIA_REPO_PASSWORD=azure://shelken-homelab/compose-sakamoto/KOPIA_REPO_PASSWORD
```

### 5. 符号链接同步问题

**问题**：rsync 默认同步符号链接本身，导致远程服务器链接失效

**修正**：在 Taskfile 的 rsync 命令添加 `-L` 参数，跟随符号链接复制实际内容
```yaml
rsync -avzL --delete ...
```

### 6. OpenList 环境变量前缀

**问题**：OpenList 的初始化配置和运行时配置使用不同的环境变量格式

**修正**：
- 初始化配置（ADMIN_PASSWORD）：使用 `OPENLIST_` 前缀
- 运行时配置（S3_ENABLE 等）：不使用前缀

```yaml
environment:
  # 运行时配置（无前缀）
  S3_ENABLE: "true"
  S3_PORT: "5246"
  # 初始化配置（OPENLIST_ 前缀）
  OPENLIST_ADMIN_PASSWORD: ${OPENLIST_ADMIN_PASSWORD}
```

## 测试命令

```bash
# 预估备份大小（dry-run）
kopia snapshot estimate /backup/data

# 手动创建快照
kopia snapshot create /backup/data

# 查看所有快照
kopia snapshot list --all
```
