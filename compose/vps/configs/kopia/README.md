# 维护 VPS Kopia 配置

日常维护按[共享维护步骤](../../../sakamoto/configs/kopia/README.md)执行，VPS 的配置来源如下

- [连接模板](repository.config.tpl)定义本机 WebDAV 入口
- [Compose 服务](../../docker-compose.yml)定义挂载、口令注入，以及对本机 `openlist` 的健康依赖
- [环境模板](../../.env.tpl)引用本机 BWS 条目
- [共享策略](../../../sakamoto/configs/kopia/policy.json)通过本目录的 `policy.json` 符号链接复用，同步方式见[部署任务](../../../../.taskfile/compose.yaml)

## 配置本机存储服务

部署前，在 VPS 的 `openlist` 网页面板中配置与集群一致的 139 存储、账号根目录和 WebDAV 权限。确认本机入口的 `main` 子目录指向同一个云端仓库

用户名和密码与本机 BWS 条目保持一致。另一台实例的网页配置不会自动同步到 VPS

## 更新凭据并部署

在仓库根目录执行以下命令。部署保留依赖检查，等待本机 `openlist` 健康后再启动 Kopia

```bash
task secret:keys secret=compose-vps
task secret:edit secret=compose-vps
task compose:deploy:vps -- --force-recreate kopia
```

共享仓库的口令一致性、首次初始化和运行验证统一见共享维护步骤
