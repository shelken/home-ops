#!/usr/bin/env bash
# 给命令补上 BWS_ACCESS_TOKEN：环境里已有就直接用（CI、手动 export），
# 否则从 1Password 读。token 能改全部服务密钥，所以不放进任何常驻环境，用到时才取。
#
# 用法: with-bws.sh <命令> [参数...]
set -euo pipefail

if [[ -z ${BWS_ACCESS_TOKEN:-} ]]; then
  BWS_ACCESS_TOKEN="$(op read "op://Projects/home-ops/BWS_ACCESS_TOKEN")"
  export BWS_ACCESS_TOKEN
fi
exec "$@"
