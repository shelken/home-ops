# 密钥管理


## sops

```bash
# 进入仓库根目录后 mise 自动提供 sops / task
task sops:encrypt-all # 一次性加密所有需要未加密文件

task sops:updatekey-all # 变更/删除/增加密钥时 一次性更新所有已加密的文件

task secret:bootstrap # 初始化集群所需的 secret
```

## 初始化所需 Secret

`task secret:bootstrap` 会根据 [`bootstrap/resources.yaml`](../bootstrap/resources.yaml) 创建集群引导阶段需要的 namespace 和 K8s Secret。外部密钥值由 [`scripts/secret-inject.py`](../scripts/secret-inject.py) 按占位符渲染：除 `azure-creds` 用 `azure://` 从 Azure KeyVault 读取外，其余都用 `bws://` 从 Bitwarden Secrets Manager 读取。渲染脚本两种占位符都支持，可在同一个文件中混用，所以执行 `task secret:bootstrap` 时 `az` 登录和 BWS 环境变量都要就绪

| 外部 secret key | 集群内资源 | 用途 | 备注 |
|-----------------|------------|------|------|
| `azure-creds` | `external-secrets/azure-creds` | External Secrets 访问 Azure KeyVault | 唯一仍读 Azure KeyVault 的 bootstrap 项；`azure-store` 保留，轮换见下文 |
| `bitwarden-access-token` | `external-secrets/bitwarden-access-token` | External Secrets 访问 Bitwarden Secrets Manager | 值取自 BWS 中同名 secret（`bws://bitwarden-access-token`），集群内 key 为 `token`，供 `bitwarden-store` 认证使用 |
| `flux-instance` | `flux-system/git-token-auth` | Flux instance 拉取 Git 仓库 | `flux-instance` 是 BWS secret 名；集群内 Secret 名是 `git-token-auth` |
| `sops` | `flux-system/sops-age` | Flux 解密 SOPS 加密资源 | `sops` 是 BWS secret 名；集群内 Secret 名是 `sops-age` |
| `ooooo-space-tls` | 由 certificates/export-import 同步 | 通配 TLS 证书 | 不在 `bootstrap/resources.yaml` 中直接创建；由证书同步链路管理 |

## Bitwarden Secrets Manager

集群内所有 ExternalSecret 与 PushSecret 都使用 ClusterSecretStore `bitwarden-store`，数据源是 BWS 项目。迁移已完成（[#1666](https://github.com/shelken/home-ops/issues/1666) 已关闭），剩余收尾（删除 `azure-store`、`azure-creds` 与 Key Vault 相关内容）见 [#1675](https://github.com/shelken/home-ops/issues/1675)。`azure-store` 仍保留，但集群内已无使用者；Azure KeyVault 只剩 `azure-creds` 和它的轮换任务。bootstrap 与 compose 模板也都读 BWS（`azure-creds` 除外），运维命令写入的同样是 BWS

BWS provider 与 Azure 的差异，写 ExternalSecret 时要遵守：

- `remoteRef.key` 是 secret 名；`property`、`version` 会被忽略，取到的永远是整段值。要取 JSON 里的键，用 `dataFrom.extract` 取整个 JSON，再用 `target.template.data` 映射
- `dataFrom.find` 不可用
- `bitwarden-store` 显示 Ready 只说明 provider 校验通过，是否可用以 ExternalSecret 同步成功为准
- 集群内只有一个 BWS 项目，同名 secret 会让 ESO 报错

渲染脚本 `scripts/secret-inject.py` 对 BWS 的约定：

- 占位符：`bws://<name>[/<json_key>]`，`name` 是 BWS secret 名（从 Azure 迁移时保持同名），值是 JSON 时用 `/<json_key>` 取键
- 环境变量：`BWS_ACCESS_TOKEN` 是机器账号访问令牌，`bws` 没有登录命令，每次调用都要带上它，所以必须由你在 shell 里提供，不进仓库。`BWS_PROJECT_ID` 是 secret 所在项目的 ID，不是凭据，已写在 [`mise.toml`](../mise.toml) 的 `[env]` 中，在仓库目录内自动生效
- CLI：`bws` 由 mise 提供，版本见 [`mise.toml`](../mise.toml)，执行 `mise install` 安装
- 脚本对整个项目只调用一次 `bws secret list`，同一项目内出现同名 secret 时报错中止

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
> [azure-key-vault](https://external-secrets.io/latest/provider/azure-key-vault/)

### azure-creds 轮换

`azure-creds` 是 External Secrets 访问 Azure KeyVault 的 bootstrap 凭据，KeyVault 中保存 JSON：`ClientID` 和 `ClientSecret`。它是唯一仍存放在 KeyVault 的 secret，`azure-creds-list` 与 `azure-creds-rotate` 是仅针对 Azure 的任务，其余 `task secret:*` 读写的都是 BWS。Azure App client secret 不能原地续期；正确流程是新增 credential、写回 KeyVault、同步 bootstrap Secret、重启 ESO，确认正常后删除旧 credential。

同一个 Azure App 只轮换 credential 时不需要重新分配 RBAC；原来的 Service Principal 角色仍然有效。只有新建 App/SP 时，才需要重新执行 KeyVault RBAC 分配。

```bash
task secret:azure-creds-list

# 会自动：新增 credential -> 写回 KeyVault -> task secret:bootstrap -> 重启 ESO -> 验证 ExternalSecret -> 删除旧 credential
task secret:azure-creds-rotate years=1
```


### 初始创建流程回忆

```bash
az login

# 创建 key vault 和资源组：
# ref：https://azure.github.io/azure-workload-identity/docs/quick-start.html#3-create-an-azure-key-vault-and-secret

# 查询自己的相关资源
az account show --query tenantId # tenantId
az group list --query "[].name" # resourceGroupName
az group list # subscriptionId
az keyvault list --query "[].name" # keyVaultName
az keyvault list --query "[].id" # role assignment scope
az keyvault show --name shelken-homelab --query location # key vault location
az ad app list --display-name [your-app-name] --query "[].appId" # 查询相关app的appid
az ad app list --query '[].{name: displayName, appid: appId}' # app 列表
az ad signed-in-user show # 查看当前自己的id信息，方便分配角色

# 创建新的 key vault
az keyvault create --name $newVaultName --resource-group $resourceGroup --location $location

# 创建一个app
az ad app create --display-name [your-app-name] --query appId -o tsv

# 根据app创建一个ServicePrincipal
az ad sp create --id $appid

# 上面两步可以简化成；create-for-rbac 会直接把client secret也一并生成。
az ad sp create-for-rbac -n [your-app-name]


# 仅读取： 给sp分配「Key Vault Secrets User」的角色
az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee $appid \
        --scope $vaultScope

# 读写： 给sp分配「Key Vault Secrets Officer」的角色
az role assignment create \
        --role "Key Vault Secrets Officer" \
        --assignee $appid \
        --scope $vaultScope

# 分配自己，object-id
az role assignment create --role "Key Vault Secrets Officer" --assignee-object-id $myObjectId --scope $scope

# 查询sp被分配角色
# az role assignment list --assignee $appid --all --output table

# 查询sp的clientid（即appid）
# az ad sp show --id $appid --query appId -o tsv

# 生成一个client secret
# NOTE: 如果使用create-for-rbac，那不需要重新生成。
# 无论是sp还是app生成的client secret，都可以使用。建议直接用app命令
az ad app credential reset \
  --id <appId 或 app 的 objectId> \
  --append \
  --display-name "<描述用途的名字>" \
  --years <有效年数> \
  --query password \
  -o tsv

az ad sp credential reset \
  --id <appId 或 app 的 objectId> \
  --append \
  --display-name "<描述用途的名字>" \
  --years <有效年数> \
  --query password \
  -o tsv

# 查询当前app生成的所有clientsecret
az ad app credential list --id $appid

# 删除不用的app
az ad app delete --id [appid]

```

```bash
# k8s 创建一个secret name=[azure-creds]
kubectl create secret -n external-secrets generic azure-creds \
--from-literal=ClientID=XXXXX \
--from-literal=ClientSecret=XXXXX --dry-run=client -o yaml \
| kubectl apply -f -

```
