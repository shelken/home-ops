## 1. 配置文件

- [x] 1.1 创建 `kopia/local/repository.config.tpl` - 本地文件系统仓库配置
- [x] 1.2 创建 `kopia/local/policy.json` - 本地备份策略（白名单路径 + 排除规则）
- [x] 1.3 更新 `.env.tpl` - 添加 `KOPIA_LOCAL_REPO_PASSWORD` 环境变量
- [x] 1.4 更新云端 `kopia/policy.json` - 排除 `/kopia-local` 目录

## 2. Docker Compose

- [x] 2.1 在 `docker-compose.yml` 中新增 `kopia-local` 服务
  - 复用 `scripts/entrypoint.sh`
  - 挂载 `kopia/local/` 配置目录
  - 挂载备份源目录（sakamoto-data）
  - 挂载备份目标目录（BackUp3T）
  - 通过 command 传入端口 51516

## 3. 文档

- [x] 3.1 更新 `kopia/README.md` - 添加本地备份服务说明

## 4. 验证（用户手动执行）

- [ ] 4.1 在 Azure Key Vault 中设置 KOPIA_LOCAL_REPO_PASSWORD
- [ ] 4.2 创建仓库目录：`ssh sakamoto "mkdir -p /Volumes/BackUp3T/kopia-local-repo"`
- [ ] 4.3 启动容器验证 Web UI 可访问 (http://sakamoto.lan:51516)
- [ ] 4.4 手动触发一次快照验证备份功能
- [ ] 4.5 确认排除规则生效（qbittorrent、VM 目录未备份）
