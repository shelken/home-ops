# Kopia 通知发送失败调试记录

**日期**: 2024-12-24
**问题**: Kopia 备份完成后，企业微信 Webhook 通知发送失败

## 问题现象

Kopia 备份服务配置了企业微信 Webhook 通知，但备份完成后未收到任何通知。

## 调试过程

### 1. 检查容器日志

```bash
docker logs kopia 2>&1 | grep -i notification
```

发现关键错误信息：
```
unable to send notification	{"err":"unable to parse message from notification template: no body found in message"}
```

### 2. 分析根本原因

检查 Kopia 通知模板格式要求。通过查看默认模板：
```bash
kopia notification template show snapshot-report.txt --original
```

发现 Kopia 通知模板必须遵循特定格式：
```
Subject: <邮件主题>

<正文内容>
```

**关键点**：
- 模板必须以 `Subject:` 开头定义主题
- `Subject:` 行后必须有一个空行
- 空行之后才是正文内容

### 3. 问题代码

原始的模板设置方式错误：
```bash
# 错误：直接输出 JSON，没有 Subject 头
TEMPLATE_BODY='{"msgtype":"text","text":{"content":"..."}}'
echo "$TEMPLATE_BODY" | kopia notification template set "snapshot-report.txt" --from-stdin
```

### 4. 修复方案

使用 heredoc 创建符合格式的模板文件：

```bash
TEMPLATE_FILE="/tmp/snapshot-report-template.txt"
cat > "$TEMPLATE_FILE" << 'TEMPLATE_EOF'
Subject: Kopia Backup {{.EventArgs.OverallStatus}}

{"msgtype":"markdown","markdown":{"content":"## Kopia 备份报告\n> **主机**: {{.Hostname}}\n> **状态**: {{.EventArgs.OverallStatus}}\n> **时间**: {{.EventTime.Format "2006-01-02 15:04:05"}}\n{{ range .EventArgs.Snapshots | sortSnapshotManifestsByName}}\n**路径**: `{{.Manifest.Source.Path}}`\n- 状态: {{.StatusCode}}\n- 大小: {{.TotalSize | bytes}}\n- 文件: {{.TotalFiles | formatCount}}\n{{ if .Error }}- 错误: {{.Error}}{{ end }}{{ end }}"}}
TEMPLATE_EOF

kopia notification template remove "snapshot-report.txt" || true
kopia notification template set "snapshot-report.txt" --from-file="$TEMPLATE_FILE"
rm -f "$TEMPLATE_FILE"
```

### 5. 日期格式优化

最初使用 `{{.EventTime | formatTime}}`，输出格式为：
```
Wed, 24 Dec 2025 07:17:00 +0800
```

改为使用 Go 模板的原生 `.Format` 方法：
```
{{.EventTime.Format "2006-01-02 15:04:05"}}
```

输出更友好的格式：
```
2024-12-24 15:30:00
```

## 关键发现

1. **Kopia 通知模板格式要求**：模板必须包含 `Subject:` 头部，后跟空行，再跟正文。这是邮件格式的遗留设计，即使使用 Webhook 也必须遵循。

2. **模板变量**：
   - `.Hostname` - 主机名
   - `.EventTime` - 事件时间（Go time.Time 类型）
   - `.EventArgs.OverallStatus` - 整体状态
   - `.EventArgs.Snapshots` - 快照列表
   - `sortSnapshotManifestsByName` - 排序过滤器
   - `.TotalSize | bytes` - 格式化大小
   - `.TotalFiles | formatCount` - 格式化文件数

3. **日期格式化**：
   - `formatTime` 默认使用 `time.RFC1123Z` 格式
   - 可使用 `.Format "layout"` 自定义格式

## 修改的文件

- `compose/scripts/kopia-entrypoint.sh` - 共享的 entrypoint 脚本
- `compose/sakamoto/scripts/entrypoint.sh` - 软链接到共享脚本
- `compose/vps/scripts/entrypoint.sh` - 软链接到共享脚本
- `compose/sakamoto/docker-compose.yml` - 挂载 entrypoint 脚本
- `compose/vps/docker-compose.yml` - 挂载 entrypoint 脚本

## 环境变量配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `KOPIA_PASSWORD` | 仓库密码 | 必填 |
| `KOPIA_WEBHOOK_URL` | 企业微信 Webhook URL | 可选，不设置则跳过通知配置 |
| `KOPIA_MIN_SEVERITY` | 通知最低级别 | `report` |

**KOPIA_MIN_SEVERITY 可选值**：
- `report`: 每次备份完成都通知（包括成功）
- `warning`: 仅在失败/警告时通知（成功时不通知）
- `error`: 仅在错误时通知

## 脚本参数

entrypoint.sh 支持传入 kopia server start 的参数：

```yaml
# 使用默认参数 (--address=0.0.0.0:51515 --without-password --insecure)
entrypoint: ["/app/scripts/entrypoint.sh"]

# 自定义参数
entrypoint: ["/app/scripts/entrypoint.sh"]
command: ["--address=0.0.0.0:8080", "--password=xxx"]
```

## 验证方法

```bash
# 创建测试快照
docker exec kopia kopia snapshot create /backup/minio --tags test:notification

# 检查日志是否有错误
docker logs kopia 2>&1 | grep -i notification | tail -5
```

成功后应在企业微信群收到格式化的 Markdown 备份报告。
