# Flux HelmRelease RetriesExceeded Stalled Cascade

**日期**: 2026-08-29
**影响**: `cloudnative-pg`、`crowdsec`、`mosquitto`、`shlink` 等多个组件因历史发布超时卡在 `Ready: False` / `Stalled: True`，导致上层 Flux `infra` 与 `apps` Kustomization 全链路短路卡死长达数周。
**发现人**: 用户

## 问题

集群多处 KS / HR 长期处于 False，但排查发现底层 Pod/Workload 实际运行正常、1/1 Ready，为什么 Flux 不会自动恢复状态？

## 现象

Flux Kustomization 报错：
```txt
health check failed: failed early due to stalled resources: [HelmRelease/database/cloudnative-pg status: 'Failed']
```

HelmRelease status 条件：
```yaml
Ready: False
Reason: UpgradeFailed / InstallFailed
Stalled: True
Reason: RetriesExceeded
Message: Failed to upgrade/install after 1 attempt(s) with no retries configured/remaining
```

## 根因

1. **默认零重试行为**：
   Flux `HelmRelease` 默认采用 `RemediateOnFailure` 策略，且 `spec.install.remediation.retries` / `spec.upgrade.remediation.retries` 默认值为 `0`。
2. **Stalled 终态拦截**：
   一旦单次 install/upgrade 超时，重试次数耗尽，`helm-controller` 将其标为 `Stalled: True`（不可自动恢复的终态）。在无人工干预或无新的 Git Spec 变更前，控制器停止对此资源的一切自动重试。
3. **Kustomize 短路**：
   上层 `kustomize-controller` 进行 healthCheck 时识别到子资源 `Stalled: True`，直接短路判负，造成 `infra` → `apps` 级联阻塞。

## 解决方案

1. **临时恢复**：
   删除 Stalled 状态的 HelmRelease 资源，触发对应 Kustomization 重新对账生成新的 Helm install/upgrade 事务。
2. **根治与防御**：
   在所有 `HelmRelease` 中显式声明 `install` 与 `upgrade` 的 `remediation`：
   ```yaml
   install:
     remediation:
       retries: -1
   upgrade:
     cleanupOnFail: true
     remediation:
       retries: 3
   ```
