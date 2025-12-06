## CloudNative-PG 立即备份

### 创建一次性备份
```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: postgres17-immediate-backup-$(date +%s)
spec:
  cluster:
    name: postgres
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
```

### 查看备份状态
```bash
# 查看所有备份
kubectl get backups -n <namespace>

# 查看备份详情
kubectl describe backup <backup-name> -n <namespace>

# 在 k9s 中查看
# 按 / 搜索 "backup" 或 "backups.backup.postgresql.cnpg.io"
```


## envoy-gateway

> [envoy-gateway-doc](https://gateway.envoyproxy.io/docs)

整个 gateway 的管理（Envoy Gateway Admin Console）

`kubectl port-forward -n network deployment/envoy-gateway 19001:19000`

访问envoy proxy admin/configdump

`kubectl port-forward -n network deployment/envoy-external 19000:19000`
