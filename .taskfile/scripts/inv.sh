#!/usr/bin/env bash
# 多处共用的 inventory 查询：只返回 ansible_host。
# 单处使用的值（lima vm/config、router ssh、LB、workers）各自本地取，不进本脚本。
#
# 用法: inv.sh <inventory-name>
# 数据: ansible/inventory/{hosts,others}.ini
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="${1:?usage: inv.sh <inventory-name>}"

json="$(
  ansible-inventory -i "${ROOT}/ansible/inventory/hosts.ini" --host "${NAME}" 2>/dev/null \
    || ansible-inventory -i "${ROOT}/ansible/inventory/others.ini" --host "${NAME}"
)" || {
  echo "inv.sh: inventory 中无主机: ${NAME}" >&2
  exit 1
}

jq -re '.ansible_host' <<<"${json}"
