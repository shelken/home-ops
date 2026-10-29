# Kopia 配置说明

## 文件结构

| 文件 | 说明 |
|------|------|
| `repository.config.tpl` | VPS 的云端 WebDAV 连接模板，与另一台宿主机连接同一个 139 `main` 库 |
| `policy.json` | 符号链接 → `../../../sakamoto/configs/kopia/policy.json` |

## 配置共享

VPS 和 sakamoto 共享同一个 Kopia 仓库和策略配置：

- **仓库密码**：两台机器各自从本机 BWS 条目读取 `KOPIA_MAIN_PASSWORD`，取值保持一致；Compose 将其作为 `KOPIA_PASSWORD` 传入 Kopia。
- **策略文件**：通过符号链接共享，rsync 使用 `-L` 参数同步实际内容
- **WebDAV 凭据**：各自读取本机 BWS 条目中的 `OPENLIST_WEBDAV_USERNAME` 和 `OPENLIST_WEBDAV_PASSWORD`；账号根目录为 `/cloud/139/backup/kopia`，连接 URL 以 `/dav/main` 结尾。
- **集群仓库**：kopiur 连接独立的 `/dav/kopiur`，凭据仅从 `volsync-template` 引入。
- **首次切换**：先初始化新的 `main` 仓库，再强制重建两台宿主机的 Kopia 服务；主机策略保留 `zstd-fastest`。

详细配置说明请参考：[sakamoto/kopia/README.md](../../../sakamoto/configs/kopia/README.md)
