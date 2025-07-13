推荐用postgres-init

```sql
grant all privileges on database [dbname] to [user] ;
```

## 恢复

1. 创建新临时cluster恢复备份。bootstrap和externalCluster。
2. 验证数据
3. 停止原cluster更新，停止应用更新（flux suspend)。删除release
4. 删除原cluster，删除临时cluster。将临时cluster验证后的配置放到原来的cluster。打开cluster的kustomization
5. 打开应用的kustomization
6. 验证。没问题，删掉恢复的相关配置。提交