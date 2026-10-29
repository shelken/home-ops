
# 升级

## system-upgrade-controller

> [k8s/infra/common/system-upgrade](/k8s/infra/common/system-upgrade/system-upgrade-controller/plans/k3s.yaml)

Plan（`plans/k3s.yaml`）里固定 `version: v1.37.1+k3s1`。

当前该控制器未部署：`k8s/infra/common/system-upgrade/kustomization.yaml` 的 `resources: []` 把 `./system-upgrade-controller/ks.yaml` 注释掉了（commit 9913bb0e“关闭 system-upgrade-controller”）。因此 k3s 版本实际由 `ansible/inventory/group_vars/all.yml` 的 `k3s_release_version`（v1.37.1+k3s1，由 Renovate 更新）经 `task bootstrap` 下发。
