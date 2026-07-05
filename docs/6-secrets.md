# 密钥管理


## sops

```shell
nix shell nixpkgs#sops nixpkgs#go-task

task sops:encrypt-all # 一次性加密所有需要未加密文件

task sops:updatekey-all # 变更/删除/增加密钥时 一次性更新所有已加密的文件

task secret:bootstrap # 初始化集群所需的 secret
```

## 初始化所需 Secret

`task secret:bootstrap` 会根据 [`bootstrap/resources.yaml`](../bootstrap/resources.yaml) 创建集群引导阶段需要的 namespace 和 K8s Secret。外部密钥值仍来自 Azure KeyVault。

| 外部 secret key | 集群内资源 | 用途 | 备注 |
|-----------------|------------|------|------|
| `azure-creds` | `external-secrets/azure-creds` | External Secrets 访问 Azure KeyVault | 引导后 ClusterSecretStore 依赖它读取外部密钥 |
| `flux-instance` | `flux-system/git-token-auth` | Flux instance 拉取 Git 仓库 | `flux-instance` 是 KeyVault remote key；集群内 Secret 名是 `git-token-auth` |
| `sops` | `flux-system/sops-age` | Flux 解密 SOPS 加密资源 | `sops` 是 KeyVault remote key；集群内 Secret 名是 `sops-age` |
| `ooooo-space-tls` | 由 certificates/export-import 同步 | 通配 TLS 证书 | 不在 `bootstrap/resources.yaml` 中直接创建；由证书同步链路管理 |

## external-secrets

> [doc](https://external-secrets.io/latest/introduction/overview/)
> [quick-start](https://external-secrets.io/latest/introduction/getting-started)
> [azure-key-vault](https://external-secrets.io/latest/provider/azure-key-vault/)

### azure-creds 轮换

`azure-creds` 是 External Secrets 访问 Azure KeyVault 的 bootstrap 凭据，KeyVault 中保存 JSON：`ClientID` 和 `ClientSecret`。Azure App client secret 不能原地续期；正确流程是新增 credential、写回 KeyVault、同步 bootstrap Secret、重启 ESO，确认正常后删除旧 credential。

```shell
task secret:azure-creds-list

task secret:azure-creds-rotate years=1

task secret:bootstrap
kubectl -n external-secrets rollout restart deploy/external-secrets
kubectl get externalsecret -A

# 确认 ExternalSecret 恢复后，删除旧 credential
task secret:azure-creds-list
az ad app credential delete --id <ClientID> --key-id <OLD_KEY_ID>
```

### 初始创建流程回忆

```shell
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

```shell
# k8s 创建一个secret name=[azure-creds]
kubectl create secret -n external-secrets generic azure-creds \
--from-literal=ClientID=XXXXX \
--from-literal=ClientSecret=XXXXX --dry-run=client -o yaml \
| kubectl apply -f -

```
