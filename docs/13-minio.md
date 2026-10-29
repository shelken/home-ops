# RustFS 对象存储

服务定义见 [Compose 配置](../compose/sakamoto/docker-compose.yml)。保留现有 S3 与控制台入口、9000/9001 端口、`MINIO_DATA_DIR` 和凭据变量，客户端无需更换配置

## 迁移与验收

- 使用独立数据副本验证目标镜像，先比较所有桶的对象清单，再使用真实业务凭据读写测试对象；根凭据可用不代表服务账号可用
- 导出 IAM 到权限为 `0600` 的文件，所在目录权限为 `0700`。RustFS 1.0.0 读取现有数据卷后，仍需通过 `mc admin cluster iam import` 导入服务账号；不得输出导出文件内容或执行 `mc alias list`
- RustFS 1.0.0 的 `mc stat <alias>/<bucket>` 容量统计可返回零；完整性验收使用 `mc ls --recursive --json`，逐项比较对象键、大小和 ETag。切换后的正常新增对象应单独计数
- APFS 克隆必须显式使用 `cp -ac`；`cp -a` 不保证写时复制。生产冷备必须在旧服务停止后制作，并放在云端与本地备份源路径以外
- Docker 虚拟机的绑定挂载会映射宿主机权限。容器内执行 `chown` 后仍需分别检查宿主机所有权和实际运行用户，并验证读写
- 切换前通过 Git 暂停两套 CNPG `ScheduledBackup`，等待 Flux 生效；确认没有运行中的物理备份，并记录两套主库的 `pg_stat_archiver` 与待归档 WAL 数量
- 停止宿主机两个 Kopia 服务，制作只读冷备，再仅启动 RustFS 并导入最新 IAM。通过 Git 创建两套 CNPG 验证备份与 Kopiur 验证快照，验收后删除临时声明并恢复调度
- 两份 Kopia 策略均忽略 `.rustfs.sys`。云端审计使用一次性容器执行策略导入和 `kopia snapshot create /backup/minio --upload-limit-mb=100`，确认上传量小于 50 MB 后才启动常驻服务
- 云端索引读取失败时保持云端服务停止，独立恢复本地备份。若 OpenList 返回通用 500，继续检查实际下载链接；189 网盘可对历史索引返回 `InfoSecurityErrorCode`。此时不得删除或重命名内容寻址的仓库文件
- RustFS 接收业务写入后，回退必须通过 S3 接口保存并回填新增对象；不得把底层对象目录当作普通文件直接混合回填。保留原始冷备，直到恢复验证完成
- 控制台根路径重定向仅匹配 `GET` 和 `HEAD`。STS 登录使用 `POST /`；重定向该请求会导致登录失败

健康接口为 `/health/ready`，控制台入口为 `/rustfs/console/`。监控名称与原有域名保留，以维持探针历史和客户端配置

## mc command

创建特定用户给特定bucket使用

```bash
vim ~/.mc/config.json
mc admin info s3

mc mb s3/$bucket_name
mc admin user add s3 $user $password

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
mc admin policy create s3 $poclic_name $policy_file

mc admin policy attach s3 $poclic_name --user $user

```

```bash
# 允许任何人读取/下载
mc anonymous set download s3/$bucket

# 复制文件
mc cp $file s3/$bucket/$file

# 文件过期策略, 文件七天后自动过期
mc ilm rule add s3/$bucket --expire-days 7
mc ilm rule ls s3/$bucket

```
