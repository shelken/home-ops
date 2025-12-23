# Kopia 配置说明

## 文件结构

| 文件 | 说明 |
|------|------|
| `repository.config.tpl` | VPS 专用的存储库连接配置，连接到本地 OpenList S3 |
| `policy.json` | 符号链接 → `../../sakamoto/kopia/policy.json` |

## 配置共享

VPS 和 sakamoto 共享同一个 Kopia 仓库和策略配置：

- **仓库密码**：VPS 引用 sakamoto 的 `KOPIA_REPO_PASSWORD`
- **策略文件**：通过符号链接共享，rsync 使用 `-L` 参数同步实际内容

详细配置说明请参考：[sakamoto/kopia/README.md](../../sakamoto/kopia/README.md)
