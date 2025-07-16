set -eo pipefail

oldVaultName=shelken-vault
newVaultName=shelken-homelab

# 获取旧Vault中所有机密的名称
secrets=$(az keyvault secret list --vault-name $oldVaultName --query "[].id" -o tsv)

# 循环遍历每个机密并迁移
for secretId in $secrets; do
    secretName=$(basename $secretId)
    echo "正在迁移机密: $secretName"
    
    # 获取旧机密的值
    secretValue=$(az keyvault secret show --name $secretName --vault-name $oldVaultName --query "value" -o tsv)
    
    # 在新Vault中创建同名机密
    az keyvault secret set --name $secretName --vault-name $newVaultName --value "$secretValue" > /dev/null
done

echo "所有机密迁移完成！"