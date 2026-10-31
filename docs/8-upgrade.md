# 集群版本升级

## system-upgrade-controller 状态

参考配置：[`k8s/infra/common/system-upgrade/system-upgrade-controller/plans/k3s.yaml`](../k8s/infra/common/system-upgrade/system-upgrade-controller/plans/k3s.yaml)

升级计划（`plans/k3s.yaml`）中的版本与 `ansible/inventory/group_vars/all.yml` 的 `k3s_release_version` 保持一致，通过以下命令查看当前目标版本：

```bash
yq '.k3s_release_version' ansible/inventory/group_vars/all.yml
```

当前该控制器处于未部署状态：`k8s/infra/common/system-upgrade/kustomization.yaml` 已将 `./system-upgrade-controller/ks.yaml` 注释关闭。目前 k3s 版本统一由 `ansible/inventory/group_vars/all.yml` 中的 `k3s_release_version` 维护，通过 `task bootstrap` 执行节点版本升级

## 控制面参数变更

k3s 启动参数在 `ansible/inventory/group_vars/` 中维护。`ansible --check --diff` 只证明声明与集群一致，不证明守护进程能用新参数启动，涉及控制面启动参数的改动必须实际重启验证；改动前先备好回滚命令，并在有观察窗的时段执行，单控制面集群参数写错会让 API 直接中断
