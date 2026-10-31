# Longhorn 降级死锁：Git 回滚有状态存储触发 webhook 互锁

**日期**: 2026-10-01
**症状关键词**: `downgrading from <NEW_VERSION> to <OLD_VERSION> is not supported`、`pending-rollback`、`failed calling webhook "validator.longhorn.io"`、`context deadline exceeded`、manager CrashLoop、依赖存储的 Kustomization 全部 False
**影响**: 全集群存储控制面瘫痪近 1 小时，所有依赖存储的 Kustomization 阻塞在 False

## 症状

```bash
flux get hr -n longhorn-system longhorn          # 卡在 pending-rollback
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=20
```

```text
pre-upgrade: failed to upgrade since downgrading from <NEW_VERSION> to <OLD_VERSION> is not supported
fatal error: downgrading from <NEW_VERSION> to <OLD_VERSION> is not supported
validator.longhorn.io: Post "https://...:9502/v1/webhook/validation?timeout=10s": context deadline exceeded
```

## 根因

- 错误假设：有状态存储组件能像无状态应用一样，用 Git 强推历史 commit 回退版本
- 实际约束：卷元数据与 CRD 单向不可逆，pre-upgrade 与启动阶段硬编码阻断跨 minor 降级；admission-webhook 端点由 `longhorn-manager` 提供，manager 镜像被降级后 CrashLoop，webhook 失去全部健康端点
- webhook 超时让 API Server 拒绝所有 Longhorn CR 的 dry-run，Flux 无法下发任何修复配置，形成「manager 崩溃 → webhook 挂死 → CR 改不了 → GitOps 修不回 manager」的环形互锁
- 缺失检查点：force-push 回退前没有核对已生效变更清单里是否含 storageclass、database、crd 这类有状态组件

## 排查陷阱

- 只看到 manager CrashLoop 就去改 Git 版本，没意识到修复本身也要经过同一个 webhook；先确认 API Server 还能不能 dry-run Longhorn CR
- 把 `pending-rollback` 当成 Flux 卡住，实际是 Helm 回滚被 pre-upgrade 校验挡住
- 新版本新增 CRD 与 ClusterRole 缺失会让 manager informer 报 Forbidden，这与降级阻断是两回事，要分开处理

## 修复

1. 先破环：就地把 `longhorn-manager` 拉回可上线版本，让 manager 起来、admission-webhook 恢复端点
2. 补齐新版本新增的 CRD 与 RBAC，解除 manager informer 的 Forbidden
3. 合并真实版本的升级 PR，让 GitOps 声明与底层有状态存储事实对齐
4. `flux reconcile ks -n longhorn-system longhorn --with-source` 触发收敛

## 护栏

- 有状态基础设施（Longhorn、CloudNative-PG 等）禁止通过 Git 回滚降级，只能向前修复；当前版本声明在 `k8s/infra/common/longhorn-system/longhorn/app/helmrelease.yaml`
- 回滚前核对已生效变更清单，含 storageclass、database、crd 类变更时禁止 force-push revert，先查官方降级支持说明
- webhook 互锁导致 GitOps 下发不了时，优先就地拉起兼容镜像恢复端点破环，不要先改 Git
- 无法写进代码：某个有状态组件能否降级由上游版本支持决定，仓库只能靠评审和变更清单核对，落不到 CI 检查
