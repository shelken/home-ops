#!/usr/bin/env bash
# 用 CRD 生成的最新 schema 严格校验 flux-local 渲染结果，拦截废弃字段与写错位置的字段。
# 用法：validate-schemas.sh <flux-local build all 的输出文件>
# CI 里用 KUBECONFORM 指定容器版命令，本地默认用 PATH 里的 kubeconform。
set -euo pipefail

rendered=${1:?用法: validate-schemas.sh <rendered.yaml>}
kubeconform=${KUBECONFORM:-kubeconform}

# flux-local 把没有值的变量替换成 ..PLACEHOLDER_X..，换成能通过格式校验的值；
# 同时丢弃渲染产生的空文档，否则 kubeconform 会报 missing kind。
sed -E \
  -e 's/\.\.PLACEHOLDER_[A-Z0-9_]*IP_V6\.\./2001:db8::1/g' \
  -e 's/\.\.PLACEHOLDER_[A-Z0-9_]*IP\.\./192.0.2.1/g' \
  -e 's/\.\.PLACEHOLDER_[A-Z0-9_]+\.\./example.com/g' \
  "$rendered" |
  yq 'select(. != null and has("kind"))' |
  $kubeconform -strict -ignore-missing-schemas -skip ConfigMapList -summary \
    -schema-location default \
    -schema-location 'https://k8s-schemas.home-operations.com/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    -
