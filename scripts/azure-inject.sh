#!/bin/bash

# render-secrets.sh (管道友好版)
# 将所有日志/进度信息重定向到 stderr (>&2)，
# 仅将最终的 YAML 内容输出到 stdout，以便通过管道传递。

# 遇到任何错误立即退出
set -eo pipefail

# 检查依赖项
command -v az >/dev/null 2>&1 || { echo >&2 "错误: 'az' (Azure CLI) 未安装或不在 PATH 中。"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "错误: 'jq' 未安装或不在 PATH 中。"; exit 1; }

# 检查是否提供了输入文件
if [ -z "$1" ];
    then
        # 将用法信息输出到 stderr
        echo >&2 "用法: $0 <template-file.yaml>"
        exit 1
fi

TEMPLATE_FILE="$1"
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo >&2 "错误: 文件 '$TEMPLATE_FILE' 未找到!"
    exit 1
fi

# 将整个模板文件读入一个变量
yaml_content=$(cat "$TEMPLATE_FILE")

# 查找所有 azure:// 占位符
placeholders=$(echo "$yaml_content" | grep -o 'azure://[a-zA-Z0-9\./_-]\+' | sort | uniq)

if [ -z "$placeholders" ]; then
    # 将提示信息输出到 stderr
    echo >&2 "未在文件中找到 'azure://' 占位符。将输出原始内容。"
    # 将原始内容输出到 stdout
    echo "$yaml_content"
    exit 0
fi

# 将所有进度信息输出到 stderr
echo >&2 "--- 正在处理占位符 ---"

for placeholder in $placeholders; do
    echo >&2 "处理: $placeholder"

    # 解析占位符路径
    path_part="${placeholder#azure://}"

    # 分割路径: vault/secret[/json_key]
    IFS='/' read -r vault_name secret_name json_key <<< "$path_part"

    # 从 Azure Key Vault 获取密钥值
    echo >&2 "  -> 获取密钥 '$secret_name' 从 Vault '$vault_name'..."
    secret_value=$(az keyvault secret show --vault-name "$vault_name" --name "$secret_name" --query 'value' -o tsv)

    # 如果指定了 json_key，则使用 jq 提取
    if [ -n "$json_key" ]; then
        echo >&2 "  -> 从 JSON 中提取 key '$json_key'..."
        # 使用 --arg 将键名安全地传递给 jq
        final_value=$(echo "$secret_value" | jq --arg key "$json_key" -r '.[$key]')
    else
        final_value="$secret_value"
    fi

    # 直接在 YAML 内容中替换占位符
    yaml_content=$(echo "$yaml_content" | sed "s|$placeholder|$final_value|g")
done

echo >&2 "--- 处理完成 ---"

# --- 关键 ---
# 将最终的、完全渲染的 YAML 输出到 stdout
# 这也是脚本唯一的 stdout 输出
echo "$yaml_content"