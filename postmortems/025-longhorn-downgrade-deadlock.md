# Longhorn 降级死锁与 Webhook 互锁

**日期**: 2026-10-01
**影响**: Longhorn 降级失败锁死在 pending-rollback，admission-webhook 失去端点导致全集群 38 个依赖存储的 Kustomization 处于 False 阻塞状态，全集群存储控制面瘫痪近 1 小时
**发现人**: shelken

## 问题
误操作升级导致 Longhorn 升至 1.13.0 后，通过 Git 强推历史 commit 触发 Helm 降级。因 Longhorn 官方严格禁止跨 minor 版本降级，导致 pre-upgrade 校验失败，manager 启动 crashloop，admission-webhook 失去就绪端点，API Server 拒绝所有 Longhorn CR 的 dry-run 请求，使得 Flux 无法应用任何后续修复配置，全集群存储依赖发生环形死锁

## 现象
最小排查命令：
```bash
# 查看 HelmRelease 状态卡在回滚
flux get hr -n longhorn-system longhorn

# 查看 manager 崩溃报错
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=20
```

关键报错信息：
- pre-upgrade hook 报错：`failed to upgrade since downgrading from v1.13.0 to v1.12.1 is not supported`
- manager 启动崩溃：`fatal error: downgrading from v1.13.0 to v1.12.1 is not supported`
- Flux dry-run 被拦截：`Internal error occurred: failed calling webhook "validator.longhorn.io": failed to call webhook: Post "https://longhorn-admission-webhook.longhorn-system.svc:9502/v1/webhook/validation?timeout=10s": context deadline exceeded`

## 根因
- 错误假设：假设有状态存储组件能够像无状态应用一样通过 Git 强推历史 commit 执行版本回退
- 实际约束：
  - Longhorn 卷元数据与 CRD 具有单向向前不可逆性，官方代码在 pre-upgrade 与启动阶段硬编码阻断跨 minor 版本降级
  - Longhorn 的 admission-webhook 依托于 longhorn-manager Pod 实例运行，当 manager 镜像被降级为 1.12 并 crashloop 时，webhook 失去全部健康端点
  - API Server 对 Longhorn CR 的校验必须经由该 webhook，webhook 超时导致 dry-run 失败，形成「manager 崩溃 -> webhook 挂死 -> 无法更新 CR -> 无法通过 GitOps 修复 manager」的环形互锁
- 缺失检查点：在执行 Git 强推回退前，未核查已生效变更中是否包含有状态存储组件

## 修复
当时应急恢复步骤：
1. 紧急打破死锁：手动将 `longhorn-manager` DaemonSet 镜像重置为 `v1.13.0`，使 manager 容器成功拉起并恢复 admission-webhook 端点
2. 补齐缺失 CRD 与 RBAC：手动应用 1.13.0 的新 CRD（如 `instancemanagerupgrades`）与 ClusterRole 权限，解除 manager informer 的 Forbidden 拦截
3. 对齐 GitOps 声明：合并 Longhorn 1.13.0 的升级 PR，让 GitOps 状态与集群底层有状态存储事实对齐
4. 触发 reconcile：执行 `flux reconcile ks -n longhorn-system longhorn --with-source` 恢复正常版本

## 预防
- 有状态基础设施（Longhorn、CloudNative-PG 等）严禁通过 Git 回滚降级，升级前确保灾备健全，升级后只能向前修复
- 回滚前检查已部署组件清单：若包含 storageclass、database、crd 类变更，禁止直接 force-push revert，必须先查阅官方降级支持说明
- 当 admission-webhook 发生循环互锁导致 Flux 无法下发时，优先通过就地拉起兼容镜像恢复 webhook 后端端点以打破死锁
