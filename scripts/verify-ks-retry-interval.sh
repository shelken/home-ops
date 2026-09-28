#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-ks-retry-interval.sh
# 遍历 k8s/ 下所有子级 Kustomization 定义（ks.yaml），确保都显式声明了 retryInterval。
# 未声明时失败重试周期退回 interval（通常 1h）：一次竞态失败就会把对象卡住一小时，
# 并通过 infra(wait:true) → apps(dependsOn) 链条冻结整个 app 层（见 2026-09-28 事故）。
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

fail_count=0

echo -e "${BLUE}--> 检查所有 ks.yaml 均显式声明 retryInterval${NC}"

while IFS= read -r -d '' f; do
  if ! grep -q 'retryInterval' "$f"; then
    echo -e "  [${RED}FAIL${NC}] $f 缺少 retryInterval"
    fail_count=$((fail_count + 1))
  fi
done < <(find k8s -name 'ks.yaml' -print0)

total=$(find k8s -name 'ks.yaml' | wc -l | tr -d ' ')

if [ "$fail_count" -eq 0 ]; then
  echo -e "  [${GREEN}PASS${NC}] $total 个 ks.yaml 全部声明了 retryInterval"
else
  echo -e "${RED}--> ${fail_count} 个文件缺少 retryInterval${NC}"
  exit 1
fi
