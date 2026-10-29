# RustFS 对象存储

宿主机 sakamoto 上运行的 RustFS 1.0.0 独立分布式对象存储实例，承接家庭集群与宿主机的全部 S3 存储需求。

- **配置定义**：[compose/sakamoto/docker-compose.yml](../compose/sakamoto/docker-compose.yml)
- **S3 API 端点**：`https://rustfs.${INTERNAL_DOMAIN}`（端口 `9000`）
- **Web 控制台**：`https://rustfs-ui.${INTERNAL_DOMAIN}/rustfs/console/`（端口 `9001`）
- **健康检查接口**：`/health/ready`（返回 HTTP 200）

---

## 核心消费者与存储桶清单

| 存储桶 (Bucket) | 消费服务 | 用途说明 |
|---|---|---|
| `cloudnative-pg` | CloudNative-PG (`postgres` / `immich-db`) | 生产主库与应用库的物理全量备份与实时 WAL 归档流 |
| `kopiur` | Kopiur 集群卷备份 | 集群 PVC 的每小时本地快照仓库（基于 Kopia pack 存储） |
| `kopia-backup` | 宿主机本地与云端备份 | 历史归档仓库桶 |
| `test` | 接口测试与探针验证 | 作为 S3 协议连通性与写入功能验收基准 |

---

## 运维与常用管理命令 (mc)

RustFS 完整兼容 AWS S3v4 API 与 MinIO Client (`mc`) 管理命令。全程在开发机通过本地 `mc` 操作，严禁直接执行 `mc alias list` 以免在终端回显密钥。

### 1. 配置管理别名

```bash
# 配置别名（使用管理员凭证）
mc alias set sakamoto-rustfs https://rustfs.${INTERNAL_DOMAIN} <ACCESS_KEY> <SECRET_KEY>

# 验证连通性与查看存储桶
mc ls sakamoto-rustfs/
```

### 2. 创建用户与授权策略

```bash
# 1. 创建存储桶
mc mb sakamoto-rustfs/$bucket_name

# 2. 创建独立服务用户
mc admin user add sakamoto-rustfs $user $password

# 3. 编写受限权限策略
cat <<EOF > policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::$bucket_name/*",
                "arn:aws:s3:::$bucket_name"
            ]
        }
    ]
}
EOF

# 4. 创建策略并绑定至用户
mc admin policy create sakamoto-rustfs $policy_name policy.json
mc admin policy attach sakamoto-rustfs $policy_name --user $user
rm -f policy.json
```

### 3. 对象生命周期规则 (ILM)

```bash
# 为指定桶添加过期规则（例如 7 天后自动删除）
mc ilm rule add sakamoto-rustfs/$bucket_name --expire-days 7

# 查看生命周期规则
mc ilm rule ls sakamoto-rustfs/$bucket_name
```
