#!/usr/bin/env bash

# azure-inject.sh (管道友好版)
# 将所有日志/进度信息重定向到 stderr (>&2)，
# 仅将最终的 YAML 内容输出到 stdout，以便通过管道传递。
#
# 优化：按 vault/secret 分组，每个 secret 只获取一次

# 遇到任何错误立即退出
set -eo pipefail

# 检查 bash 版本 (需要 4.0+ 支持关联数组)
if ((BASH_VERSINFO[0] < 4)); then
    echo >&2 "错误: 需要 bash 4.0 或更高版本 (当前: $BASH_VERSION)"
    exit 1
fi

# 检查依赖项
command -v az >/dev/null 2>&1 || { echo >&2 "错误: 'az' (Azure CLI) 未安装或不在 PATH 中。"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "错误: 'jq' 未安装或不在 PATH 中。"; exit 1; }

# 检查是否提供了输入文件
if [ -z "$1" ]; then
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

# 查找所有 azure:// 占位符（grep 无匹配时返回 1，需要忽略）
placeholders=$(echo "$yaml_content" | grep -o 'azure://[a-zA-Z0-9\./_-]\+' | sort | uniq || true)

if [ -z "$placeholders" ]; then
    echo >&2 "未在文件中找到 'azure://' 占位符。将输出原始内容。"
    echo "$yaml_content"
    exit 0
fi

# 声明关联数组用于缓存已获取的密钥
declare -A secret_cache

# 第一阶段：收集所有需要的 vault/secret 组合并批量获取
echo >&2 "--- 正在获取密钥 ---"

# 收集唯一的 vault/secret 组合
unique_secrets=$(echo "$placeholders" | while read -r placeholder; do
    path_part="${placeholder#azure://}"
    IFS='/' read -r vault_name secret_name json_key <<< "$path_part"
    echo "${vault_name}/${secret_name}"
done | sort | uniq)

# 批量获取每个唯一的 secret
for vault_secret in $unique_secrets; do
    IFS='/' read -r vault_name secret_name <<< "$vault_secret"
    cache_key="${vault_name}/${secret_name}"

    echo >&2 "获取: ${vault_name}/${secret_name}"
    secret_value=$(az keyvault secret show --vault-name "$vault_name" --name "$secret_name" --query 'value' -o tsv)
    secret_cache["$cache_key"]="$secret_value"
done

# 第二阶段：使用缓存的密钥值进行替换
echo >&2 "--- 正在替换占位符 ---"

for placeholder in $placeholders; do
    # 解析占位符路径
    path_part="${placeholder#azure://}"
    IFS='/' read -r vault_name secret_name json_key <<< "$path_part"

    cache_key="${vault_name}/${secret_name}"
    secret_value="${secret_cache[$cache_key]}"

    # 如果指定了 json_key，则使用 jq 提取
    if [ -n "$json_key" ]; then
        final_value=$(echo "$secret_value" | jq --arg key "$json_key" -r '.[$key]')
    else
        final_value="$secret_value"
    fi

    # 直接在 YAML 内容中替换占位符
    yaml_content=$(echo "$yaml_content" | sed "s|$placeholder|$final_value|g")
done

echo >&2 "--- 处理完成 ---"

# 将最终的、完全渲染的内容输出到 stdout
echo "$yaml_content"