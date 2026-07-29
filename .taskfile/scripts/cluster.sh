#!/usr/bin/env bash
# k3s worker 启停（PVE）。control-plane 由 lima:* 负责。
#
# 用法: cluster.sh status|stop-workers|start-workers|wait-api|wait-nodes
# 环境: STOP_WAIT_SEC START_WAIT_SEC（可选）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
K8S_INV="${ROOT}/ansible/inventory/hosts.ini"
MACH_INV="${ROOT}/ansible/inventory/others.ini"
STOP_WAIT_SEC="${STOP_WAIT_SEC:-90}"
START_WAIT_SEC="${START_WAIT_SEC:-120}"

pve_ssh() {
  ansible-inventory -i "${MACH_INV}" --host pve \
    | jq -re '.ansible_user + "@" + .ansible_host'
}

# TSV: name ip user
workers() {
  ansible-inventory -i "${K8S_INV}" --list | jq -r '
    ._meta.hostvars as $h
    | .workers.hosts[]?
    | "\(.)\t\($h[.].ansible_host)\t\($h[.].ansible_user)"'
}

vmid_for_ip() {
  local ip="$1" conf
  conf="$(ssh "${PVE}" "grep -l 'ip=${ip}/' /etc/pve/qemu-server/*.conf | head -1")"
  [ -n "${conf}" ] || {
    echo "cluster.sh: PVE 无 ip=${ip}/ 的 VM" >&2
    return 1
  }
  basename "${conf}" .conf
}

qm_status() {
  ssh "${PVE}" "qm status ${1}"
}

wait_qm() {
  local vmid="$1" want="$2" i st
  for i in $(seq 1 "${STOP_WAIT_SEC}"); do
    st="$(qm_status "${vmid}" 2>/dev/null || true)"
    echo "  [${i}] ${st}"
    case "${st}" in
      *"status: ${want}"*) return 0 ;;
    esac
    sleep 1
  done
  return 1
}

cmd_status() {
  local node ip vmid
  echo "=== PVE workers ==="
  while IFS=$'\t' read -r node ip _; do
    [ -n "${node:-}" ] || continue
    if vmid="$(vmid_for_ip "${ip}")"; then
      echo "${node}  ip=${ip}  vmid=${vmid}  $(qm_status "${vmid}" 2>/dev/null || echo unknown)"
    else
      echo "${node}  ip=${ip}  vmid=?"
    fi
  done < <(workers)
  echo
  echo "=== k3s nodes ==="
  kubectl get nodes -o wide 2>/dev/null || echo "(API 不可达)"
}

cmd_stop_workers() {
  local node ip vmid
  while IFS=$'\t' read -r node ip _; do
    [ -n "${node:-}" ] || continue
    vmid="$(vmid_for_ip "${ip}")"
    echo "--- stop ${node} vmid=${vmid} ---"

    # 幂等：已 stopped 则跳过
    case "$(qm_status "${vmid}")" in
      *stopped*) echo "already stopped"; continue ;;
    esac

    if kubectl get node "${node}" >/dev/null 2>&1; then
      kubectl drain "${node}" \
        --ignore-daemonsets --delete-emptydir-data --force \
        --grace-period=30 --timeout=120s || echo "WARN: drain 失败，继续关机"
    fi

    # 单一路径：PVE ACPI 关机（guest SSH 不可达时也能用）
    ssh "${PVE}" "qm shutdown ${vmid} --timeout 60" || true
    wait_qm "${vmid}" stopped || {
      echo "WARN: 强制 qm stop"
      ssh "${PVE}" "qm stop ${vmid}"
    }
  done < <(workers)
}

cmd_start_workers() {
  local node ip vmid
  while IFS=$'\t' read -r node ip _; do
    [ -n "${node:-}" ] || continue
    vmid="$(vmid_for_ip "${ip}")"
    case "$(qm_status "${vmid}")" in
      *running*) echo "${node} already running"; continue ;;
    esac
    echo "--- start ${node} vmid=${vmid} ---"
    ssh "${PVE}" "qm start ${vmid}"
  done < <(workers)
}

cmd_wait_api() {
  local i
  for i in $(seq 1 "${START_WAIT_SEC}"); do
    if kubectl get --raw=/readyz >/dev/null 2>&1; then
      echo "✓ API ready"
      return 0
    fi
    sleep 1
  done
  echo "cluster.sh: API ${START_WAIT_SEC}s 未就绪" >&2
  return 1
}

cmd_wait_nodes() {
  local name
  kubectl wait --for=condition=Ready nodes --all --timeout="${START_WAIT_SEC}s"
  # 未 cordon 的 uncordon 亦安全
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    kubectl uncordon "${name}" || true
  done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  kubectl get nodes -o wide
}

main() {
  PVE="$(pve_ssh)"
  case "${1:-}" in
    status) cmd_status ;;
    stop-workers) cmd_stop_workers ;;
    start-workers) cmd_start_workers ;;
    wait-api) cmd_wait_api ;;
    wait-nodes) cmd_wait_nodes ;;
    *)
      echo "usage: cluster.sh status|stop-workers|start-workers|wait-api|wait-nodes" >&2
      exit 1
      ;;
  esac
}

main "$@"
