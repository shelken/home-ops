# 运维实用技巧

## CloudNativePG 立即备份

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


## Envoy Gateway 调试与控制台

参考上游文档：[Envoy Gateway Docs](https://gateway.envoyproxy.io/docs)

管理控制台端口转发（Envoy Gateway Admin Console）：

```bash
kubectl port-forward -n network deployment/envoy-gateway 19001:19000
```

查看 Envoy Proxy 实际运行配置（admin / config_dump）：

```bash
kubectl port-forward -n network deployment/envoy-external 19000:19000
```
