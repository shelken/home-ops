## mc command

创建特定用户给特定bucket使用

```shell
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

```shell
# 允许任何人读取/下载
mc anonymous set download s3/$bucket

# 复制文件
mc cp $file s3/$bucket/$file

# 文件过期策略, 文件七天后自动过期
mc ilm rule add s3/$bucket --expire-days 7
mc ilm rule ls s3/$bucket

```