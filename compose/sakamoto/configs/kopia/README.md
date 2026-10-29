# 维护 Kopia 备份配置

在仓库根目录执行 `task` 命令，在目标主机的 Compose 目录执行 `docker compose` 命令

## 找到配置来源

- [Compose 服务](../../docker-compose.yml)定义备份卷、端口、容器环境变量和配置挂载
- [环境模板](../../.env.tpl)定义本机 BWS 字段引用
- [云端连接模板](repository.config.tpl)定义共享 `main` 仓库入口，[云端策略](policy.json)定义调度、保留、压缩和排除规则
- [本地连接模板](local/repository.config.tpl)与[本地策略](local/policy.json)定义 `kopia-local` 的仓库和备份范围
- [启动脚本](entrypoint.sh)定义连接检查、策略导入和通知配置
- [集群部署入口](../../../../k8s/infra/common/kopiur-system/kopiur/ks.yaml)定义云端仓库先就绪、集中复制后同步的依赖顺序

两台宿主机通过各自的存储入口访问同一个 `main` 仓库，口令值必须一致，各自从本机 BWS 条目引入凭据。VPS 使用本机的存储服务，配置前提见 [VPS 配置入口](../../../vps/configs/kopia/README.md)

集群凭据由[云端 ExternalSecret](../../../../k8s/infra/common/kopiur-system/kopiur/repository-cloud/externalsecret.yaml)引入，与宿主机分开维护

## 更新凭据

先查看字段名，再编辑对应的 BWS 条目

```bash
task secret:keys secret=compose-sakamoto
task secret:edit secret=compose-sakamoto
```

口令字段及其容器变量映射以环境模板和 Compose 服务为准

## 更新配置并重建服务

修改连接模板或对应的策略文件后，执行目标主机的部署任务

```bash
task compose:deploy:sakamoto -- --no-deps --force-recreate kopia
```

更新本地备份时，将末尾的服务名改为 `kopia-local`

配置文件通过 Compose `configs` 挂载。修改文件内容后仍需强制重建容器，才能加载新内容。[部署任务](../../../../.taskfile/compose.yaml)负责渲染模板、跟随符号链接同步文件和清理本地渲染产物

## 验证运行结果

在目标主机查询仓库、策略和快照，不在本文保存状态输出

```bash
docker compose exec kopia kopia repository status
docker compose exec kopia kopia policy list
docker compose exec kopia kopia snapshot list --all
```

检查压缩或保留策略时，从 `policy list` 选择目标，再执行 `policy show`。全局策略不包含主机和路径的覆盖项

```bash
docker compose exec kopia kopia policy show --global
docker compose exec kopia kopia policy show '@<host>'
```

将 `@<host>` 替换为实际策略目标。检查本地备份时，将服务名改为 `kopia-local`

## 首次连接新仓库

先初始化宿主机的新仓库，再启动服务。启动脚本只检查连接，不会自动建库。共享的 `main` 只需初始化一次，后续客户端连接已有仓库

集群仓库由 Kopiur 的 bootstrap 负责创建和连接，创建权限在[仓库声明](../../../../k8s/infra/common/kopiur-system/kopiur/repository-cloud/clusterrepository.yaml)中维护。等待仓库 Ready 后，再验证策略并启用复制

复用旧缓存切换仓库后，检查新库是否已有策略。启动脚本的策略与通知指纹不包含仓库身份，重建容器不会清空持久化缓存。缺少策略时，使用[启动脚本中的导入命令](entrypoint.sh)导入，再查询实际策略

集群复制的暂停状态和策略复制选项以 [SnapshotReplication](../../../../k8s/infra/common/kopiur-system/kopiur/replication/snapshotreplication.yaml) 为准。复制未携带源策略时，先配置并验证目标库的压缩策略，再通过 Git 启用复制

读取历史仓库时，保留原来的后端类型、目录布局和口令。修改连接类型不会转换存量数据

## 排查客户端同步延迟

另一客户端暂时看不到新快照时，先比较两端 `repository status` 的仓库身份。确认连接同一仓库后，再重新连接受影响的客户端并查询快照
