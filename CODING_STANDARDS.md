# 编码与约定

适用于本仓库的 GitOps 声明、脚本与文档变更。架构与拓扑事实见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，文档约定见 [docs/README.md](docs/README.md)

## 环境与远程操作

- 环境变量与 CLI（含 kubeconfig）由 mise 管理，声明见根目录 `mise.toml`
- SSH 执行命令优先用 IP 而非主机名，地址以 `ansible/inventory/hosts.ini` 为准

## 目录与模块归属

- 谁负责干这件事，文件就放谁那里，不看文件类型，也不看依赖哪个技术栈（如 `zte-mifi-exporter` 的告警规则放在它自己的 `app/` 里，不管这条规则属于 Prometheus 还是 Gatus）
- 每个 app 固定两层：`<app-name>/ks.yaml` 作为 Flux 入口，其余资源放 `app/`
- 同一目的的多个服务放在同一应用目录，按职责拆子目录（如 `xxx/app/`、`xxx/login/`），由同级 `ks.yaml` 引用

## 集群外资产

- 一个功能 = 一份声明 + 一个下发器 + 一个 task 命名空间 + 一篇文档，`router/` 是样板
- 先界定远端所有权，独占文件或目录才能整体替换，共享配置只在专用附加目录里持续声明
- 只服务单一功能的脚本、模板与数据跟声明同目录，跨功能复用的才进 `scripts/`
- 远端路径只在 taskfile 里定义一次，声明目录必须标明对应的远端所有权范围

## Flux 资源

- 集群状态以 Flux 已同步的内容为准，本地未提交或未推送的修改不代表集群
- HelmRelease 失败时不要反复 reconcile：删除该 HelmRelease 后执行 `flux reconcile ks` 重建

## 镜像与依赖

- 需要新镜像时用 crane 查询，版本固定为 semver@digest，升级交给 Renovate
- 在 `k8s/apps/common/` 启用或禁用应用时，同步更新 `.renovate/packageRules.json5` 的 Disabled Packages：禁用加入该应用的镜像与包，启用时移除

## 密钥与安全

- 所有配置默认最小权限；权限提升或新增安全敏感配置，必须引用官方文档、配置参考或发布日志并附来源链接

## 网络与 DNS

- 手动 DNS（非 External-DNS 管理）配置在本地 `{active-dir}/dnscontrol`；任何手动 DNS 变更必须先经用户确认并展示变化范围

## 参考

- [`onedr0p/home-ops`](https://github.com/onedr0p/home-ops)：架构与配置模式的上游参考，本地在 `{kaiyuan-dir}/homelab/home-ops`，每次先拉最新再看
