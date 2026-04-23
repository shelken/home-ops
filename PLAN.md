# Checkpoints

# Checkpoints

## 1. 抽离 ip-selector 脚本
- [x] 新增 `k8s/infra/common/network/external/caddy-external/app/resources/ip-selector.sh`
- [x] 更新 `k8s/infra/common/network/external/caddy-external/app/kustomization.yaml` 生成脚本 ConfigMap
- [x] 确认脚本里的命令在 `busybox:stable` 中可用：`/bin/sh`、`wget`、`sleep`、`cat`、`nc`

## 2. HelmRelease 恢复原有双容器结构
- [x] 恢复 `ip-selector` + `ddns`
- [x] 保持逻辑为：只要不是 `2408:` 就写入 VPS IPv6，探测失败也写入 VPS IPv6
- [x] 不再做 AAAA 清理逻辑

## 3. 验证
- [x] 运行格式/校验：`sh -n`、`shellcheck`、`kustomize build` 已通过
- [x] 运行 `pre-commit run --files` 覆盖本次变更文件
- [x] 修正 `set -e` 下后台刷新循环在首次探测失败后提前退出的问题
- [x] 审阅最终 diff 仅包含目标改动

# Plan

1. 新建 `ip-selector.sh`，仅保留地址选择逻辑：`2408:` 用家宽 IPv6，其余情况统一写入 `${MAIN_VPS_IP_V6}`，探测失败也写入 `${MAIN_VPS_IP_V6}`。
2. 在 `app/kustomization.yaml` 里改为生成 `ip-selector.sh` 的 ConfigMap。
3. 在 `app/helmrelease.yaml` 里恢复 `ip-selector` 与 `ddns` 两个容器，并让 `ip-selector` 通过挂载脚本启动。
4. 保留 `/tmp` emptyDir 与本地 8888 HTTP 提供给 `ddns` 读取，不做清理逻辑。
5. 运行 YAML/脚本相关校验与 `pre-commit`，检查 diff 范围。
