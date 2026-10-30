# 密钥管理


## SOPS

```bash
# 进入仓库根目录后 mise 自动提供 sops 与 task
task sops:encrypt-all    # 批量加密未加密的 SOPS 目标文件
task sops:updatekey-all  # 密钥变更时批量更新已加密文件
task secret:bootstrap    # 渲染并应用集群自举所需 Secret
```

## 初始化所需 Secret

`task secret:bootstrap` 会根据 [`bootstrap/resources.yaml`](../bootstrap/resources.yaml) 创建集群引导阶段需要的 namespace 和 K8s Secret。外部密钥值由 [`scripts/secret-inject.py`](../scripts/secret-inject.py) 按 `bws://` 占位符从 Bitwarden Secrets Manager 读取。执行前必须配置 `BWS_ACCESS_TOKEN`，并通过 mise 注入 `BWS_PROJECT_ID`

| 外部 secret key | 集群内资源 | 用途 | 备注 |
|-----------------|------------|------|------|
| `bitwarden-access-token` | `external-secrets/bitwarden-access-token` | External Secrets 访问 Bitwarden Secrets Manager | 值取自 BWS 中同名 secret（`bws://bitwarden-access-token`），集群内 key 为 `token`，供 `bitwarden-store` 认证使用 |
| `flux-instance` | `flux-system/git-token-auth` | Flux instance 拉取 Git 仓库 | `flux-instance` 是 BWS secret 名；集群内 Secret 名是 `git-token-auth` |
| `sops` | `flux-system/sops-age` | Flux 解密 SOPS 加密资源 | `sops` 是 BWS secret 名；集群内 Secret 名是 `sops-age` |
| `ooooo-space-tls` | 由 certificates/export-import 同步 | 通配 TLS 证书 | 不在 `bootstrap/resources.yaml` 中直接创建；由证书同步链路管理 |

## Bitwarden Secrets Manager

集群内所有 ExternalSecret 与 PushSecret 都使用 ClusterSecretStore `bitwarden-store`，数据源是 BWS 项目。bootstrap、compose 模板和 `task secret:*` 的读写也使用 BWS。仓库不再提供 Azure Key Vault 的 store、bootstrap 凭据或轮换任务

BWS provider 的使用约束：

- `remoteRef.key` 为 secret 名；`property` 与 `version` 会被忽略，取到的始终为整段值。若需消费 JSON 字段，使用 `dataFrom.extract` 提取整个 JSON，再通过 `target.template.data` 映射
- 不支持 `dataFrom.find`
- `bitwarden-store` 处于 Ready 只说明 store 校验通过，实际可用性以具体 ExternalSecret 同步成功为准
- 单一项目内出现同名 secret 会导致 ESO 报错

渲染脚本 `scripts/secret-inject.py` 约定：

- 占位符：`bws://<name>[/<json_key>]`，`name` 为 BWS secret 名，值为 JSON 时以 `/<json_key>` 取键
- 环境变量：`BWS_ACCESS_TOKEN` 为机器账号访问令牌，由外部 shell 提供，不提交仓库；`BWS_PROJECT_ID` 为项目 ID，已由 [`mise.toml`](../mise.toml) 注入
- CLI：`bws` 由 mise 统一管理
- 脚本运行期间单次拉取 `bws secret list`，检测到同名 secret 即中止报错

```bash
export BWS_ACCESS_TOKEN=<机器账号令牌>
task secret:bootstrap
```

### 写入命令

写入由 [`scripts/secret-store.py`](../scripts/secret-store.py) 完成，`task secret:*` 都调用它，同样需要 `BWS_ACCESS_TOKEN` 与 `BWS_PROJECT_ID`。一个 BWS secret 存一个 JSON 对象，按键增删改；写入前校验 JSON，同名 secret 拒绝写入，空值拒绝写入，除 `show` 外不打印值：

```bash
task secret:azsecret [key=<name>]                 # 不带 key 列出所有 secret 名，带 key 显示该 secret 的值
task secret:keys secret=<name>                    # 只看有哪些键，不显示值
task secret:set-key secret=<name> key=<k> value=<v> # secret 不存在则创建，键已存在则更新
task secret:edit secret=<name>                    # 用 $EDITOR 编辑，内容有变化且是合法 JSON 才写入
task secret:delete-key secret=<name> key=<k>
task secret:delete [key=<name>]                   # 不带 key 时用 fzf 选择
```

## external-secrets

> [doc](https://external-secrets.io/latest/introduction/overview/)
> [quick-start](https://external-secrets.io/latest/introduction/getting-started)
> [Bitwarden Secrets Manager provider](https://external-secrets.io/latest/provider/bitwarden-secrets-manager/)

## Azure 资源保留范围

仓库收尾只删除闲置的 Azure 声明、注入支持和运维工具。合并后，Flux 会回收 `azure-store` Kustomization、ClusterSecretStore 和原 Azure PrometheusRule；通用同步失败告警保留在 BWS 规则文件中

以下资源不随本次 PR 删除：

- Azure Key Vault 及其中的 secret，包括 `azure-creds`
- Azure App、credential、Service Principal 和 Key Vault RBAC 授权
- 集群中的 `external-secrets/azure-creds` Secret，由旧 bootstrap 创建，不在 Flux inventory 中，删除前必须单独确认

保留 Azure 云端资源用于后续人工清理，集群没有自动回退到 Azure 的配置。后续删除必须单独确认；BWS 切换后更新的值不会反向同步到 Azure，因此保留的数据不保证与 BWS 当前值一致
