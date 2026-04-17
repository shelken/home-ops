# 检查点

## 1. 策略迁移到 envoy-gateway/policy

- 状态：已完成
- 验证：`ClientTrafficPolicy` 已迁移到 `k8s/infra/common/network/envoy-gateway/policy/`，并在 `k8s/infra/common/network/envoy-gateway/ks.yaml` 新增独立 Flux `Kustomization` 以 `network` 命名空间下发。

## 2. 删除应用侧错误归属

- 状态：已完成
- 验证：`k8s/apps/common/cli-proxy-api/app/clienttrafficpolicy.yaml` 已删除，`k8s/apps/common/cli-proxy-api/app/kustomization.yaml` 不再引用该策略。

## 3. 校验

- 状态：已完成
- 验证：`kustomize build k8s/apps/common/cli-proxy-api/app`、`kustomize build k8s/infra/common/network/envoy-gateway/policy` 成功；`ruby` 解析 `k8s/infra/common/network/envoy-gateway/ks.yaml` 成功；`pre-commit run --files ...` 全通过。

# 实现步骤

1. 新建 `k8s/infra/common/network/envoy-gateway/policy/`，放置 `ClientTrafficPolicy` 与 `kustomization.yaml`，并在 `ks.yaml` 接入
2. 删除 `k8s/apps/common/cli-proxy-api/app/` 下的策略文件与引用
3. 执行构建校验并回写检查点结果
