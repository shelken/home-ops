# 密钥管理


## sops

```shell
nix shell nixpkgs#sops nixpkgs#go-task

task encrypt-all # 一次性加密所有需要未加密文件

task updatekey-all # 变更/删除/增加密钥时 一次性更新所有已加密的文件

task deploy-secret # 将sops-age部署到flux-system
```

## external-secrets

> [doc](https://external-secrets.io/latest/introduction/overview/)
> [quick-start](https://external-secrets.io/latest/introduction/getting-started)
> [azure-key-vault](https://azure.github.io/azure-workload-identity/docs/quick-start.html#6-establish-federated-identity-credential-between-the-identity-and-the-service-account-issuer--subject)
> [azure-key-vault](https://example.com)

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

# 创建一个app
az ad app create --display-name [your-app-name] --query appId -o tsv
# az ad app list --display-name [your-app-name] --query "[].appId"

# 根据app创建一个ServicePrincipal
az ad sp create --id $appid

# 上面两步可以简化成；create-for-rbac 会直接把client secret也一并生成。
az ad sp create-for-rbac -n [your-app-name]
az ad app list --query '[].{name: displayName, appid: appId}'

# 给sp分配「Key Vault Secrets User」的角色
az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee "$appid" \
        --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.KeyVault/vaults/$keyVaultName"

# 查询sp被分配角色
# az role assignment list --assignee [id-or-appid] --all --output table

# 查询sp的clientid（即appid）
# az ad sp show --id [id-or-appid] --query appId -o tsv

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
az ad app credential list --id [id-or-appid]

# 删除不用的app
az ad app delete --id [appid]

```

```shell
# k8s 创建一个secret name=[azure-creds]
kubectl create secret -n external-secrets generic azure-creds \                                        
--from-literal=ClientID=XXXXX \
--from-literal=ClientSecret=XXXXX --dry-run=client -o yaml \
| kubectl apply -f -

``