# Renovate 自动化升级

Renovate 自动化升级由 GitHub Actions 驱动，配置文件位于根目录 [`.renovaterc.json5`](../.renovaterc.json5)，自定义分组与规则位于 [`.renovate/`](../.renovate/)

新增或禁用 `k8s/apps/common/` 下的服务时，需同步维护 `.renovate/packageRules.json5` 的规则与排除项
