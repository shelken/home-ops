#!/bin/sh

# 遇到错误立即退出
set -e

# 恢复配置模板
cp /app/config/repository.config.tpl /app/config/repository.config

# 连接仓库
# 使用容器的主机名 (在 docker-compose 中设置的 hostname) 作为 override-hostname
CURRENT_HOST=$(hostname)
echo "正在连接 Kopia 仓库，主机名: $CURRENT_HOST..."

kopia repository connect from-config --file /app/config/repository.config --override-hostname="$CURRENT_HOST" --override-username=shelken || \
kopia repository create from-config --file /app/config/repository.config

# 导入策略
echo "正在导入策略..."
kopia policy import --from-file /app/config/policy.json

# 如果设置了 Webhook URL，则配置通知
if [ -n "$KOPIA_WEBHOOK_URL" ]; then
    echo "正在配置企业微信 Webhook 通知..."
    
    # 配置通知 Profile
    # 使用 txt 格式，因为我们将手动构建 JSON
    # KOPIA_MIN_SEVERITY 选项:
    #   - report: 每次备份完成都通知（包括成功）（默认值）
    #   - warning: 仅在失败/警告时通知（成功时不通知）
    #   - error: 仅在错误时通知
    KOPIA_MIN_SEVERITY="${KOPIA_MIN_SEVERITY:-report}"
    kopia notification profile configure webhook \
        --profile-name="wecom_webhook" \
        --endpoint="$KOPIA_WEBHOOK_URL" \
        --method="POST" \
        --http-header="Content-Type: application/json" \
        --format="txt" \
        --min-severity="$KOPIA_MIN_SEVERITY"

    # 设置模板
    # Kopia 模板必须包含 Subject: 头 + 空行 + 正文
    # 正文部分是企业微信 Webhook 接受的 JSON
    # 模板变量: .Hostname, .EventTime, .EventArgs.OverallStatus, .EventArgs.Snapshots 等

    # 创建模板文件 (使用 heredoc 保持格式)
    TEMPLATE_FILE="/tmp/snapshot-report-template.txt"
    cat > "$TEMPLATE_FILE" << 'TEMPLATE_EOF'
Subject: Kopia Backup {{.EventArgs.OverallStatus}}

{"msgtype":"markdown","markdown":{"content":"## Kopia 备份报告\n> **主机**: {{.Hostname}}\n> **状态**: {{.EventArgs.OverallStatus}}\n> **时间**: {{.EventTime.Format "2006-01-02 15:04:05"}}\n{{ range .EventArgs.Snapshots | sortSnapshotManifestsByName}}\n**路径**: `{{.Manifest.Source.Path}}`\n- 状态: {{.StatusCode}}\n- 大小: {{.TotalSize | bytes}}\n- 文件: {{.TotalFiles | formatCount}}\n{{ if .Error }}- 错误: {{.Error}}{{ end }}{{ end }}"}}
TEMPLATE_EOF

    # Remove existing template to ensure update
    kopia notification template remove "snapshot-report.txt" || true
    kopia notification template set "snapshot-report.txt" --from-file="$TEMPLATE_FILE"
    rm -f "$TEMPLATE_FILE"
        
    echo "通知配置完成: wecom_webhook"
else
    echo "未设置 KOPIA_WEBHOOK_URL，跳过通知配置。"
fi

# 启动服务器
echo "正在启动 Kopia Server..."
# 默认参数：无密码模式，方便内网访问
# 可通过传入参数覆盖，例如: entrypoint.sh --address=0.0.0.0:8080 --password=xxx
if [ $# -eq 0 ]; then
    exec kopia server start --address=0.0.0.0:51515 --without-password --insecure
else
    exec kopia server start "$@"
fi
