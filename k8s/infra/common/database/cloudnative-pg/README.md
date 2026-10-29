# CloudNativePG 运维与恢复指南

业务数据库推荐使用 `postgres-init` 初始化容器管理权限：

```sql
grant all privileges on database [dbname] to [user];
```

## 备份恢复流程

1. 创建临时 Cluster 资源恢复备份，配置 `bootstrap` 与 `externalCluster`
2. 验证恢复后的临时集群数据一致性
3. 暂停原集群更新与应用更新（`flux suspend`），清理旧 Release
4. 删除原 Cluster 与临时 Cluster，将临时 Cluster 验证后的有效配置合并回主集群 Cluster，恢复 Cluster 所在 Kustomization
5. 恢复业务应用的 Kustomization
6. 验证业务就绪后，清理临时恢复配置并提交 Git
