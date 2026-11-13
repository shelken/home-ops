#!/usr/bin/env bash
# 用 CRD 生成的最新 schema 严格校验渲染结果，拦截废弃字段与写错位置的字段。
# 用法：validate-schemas.sh <flate build 的输出文件>
# CI 里用 KUBECONFORM 指定容器版命令，本地默认用 PATH 里的 kubeconform。
set -euo pipefail

rendered=${1:?用法: validate-schemas.sh <rendered.yaml>}
kubeconform=${KUBECONFORM:-kubeconform}

yq 'select(. != null and has("kind"))' "$rendered" |
  $kubeconform -strict -ignore-missing-schemas -skip ConfigMapList -summary \
    -schema-location default \
    -schema-location 'https://k8s-schemas.home-operations.com/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    -
