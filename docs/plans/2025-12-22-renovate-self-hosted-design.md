# Renovate 自托管迁移设计方案

## 概述

将 Renovate 从 Mend 托管迁移到 GitHub Actions 自托管，以获得更高的运行频率和更好的控制权。

### 迁移目标

| 对比项 | Mend 托管 (现状) | 自托管 (目标) |
|--------|-----------------|---------------|
| 运行频率 | 每周末 | 每小时 |
| 触发方式 | Mend 平台控制 | GitHub Actions (cron + push + 手动) |
| 认证方式 | Mend App | 自有 GitHub App |
| 调试能力 | 有限 | 完整日志 + dry-run |

---

## 文件变更

```
.github/workflows/renovate.yaml  # 新增
.renovaterc.json5                # 移除 schedule 配置
```

---

## GitHub App 权限配置

在现有的 Bot App 上添加以下权限：

| 权限 | 级别 | 用途 |
|------|------|------|
| Contents | Read and write | 推送代码、创建分支 |
| Issues | Read and write | 管理 Dependency Dashboard |
| Pull requests | Read and write | 创建和更新 PR |
| Workflows | Read and write | 更新 GitHub Actions |
| Metadata | Read-only | 基础访问 |

**操作步骤：**
1. 访问 GitHub → Settings → Developer settings → GitHub Apps
2. 选择 Bot App
3. 在 Permissions & events 中更新上述权限
4. 保存后在仓库的 App 安装设置中重新授权

---

## Workflow 文件

`.github/workflows/renovate.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/github-workflow.json
name: Renovate

on:
  push:
    branches:
      - main
    paths:
      - .renovaterc.json5
      - .renovate/**
  schedule:
    - cron: "0 * * * *"
  workflow_dispatch:
    inputs:
      dryRun:
        description: Dry Run
        type: boolean
        default: false
        required: true
      logLevel:
        description: Log Level
        type: choice
        default: debug
        options:
          - debug
          - info
        required: true
      version:
        description: Renovate Version
        default: latest
        required: true

concurrency:
  group: ${{ github.workflow }}-${{ github.event.number || github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  renovate:
    name: Renovate
    runs-on: ubuntu-latest
    steps:
      - name: Generate Token
        uses: actions/create-github-app-token@29824e69f54612133e76f7eaac726eef6c875baf # v2.2.1
        id: app-token
        with:
          app-id: ${{ secrets.BOT_APP_ID }}
          private-key: ${{ secrets.BOT_APP_PRIVATE_KEY }}

      - name: Checkout
        uses: actions/checkout@8e8c483db84b4bee98b60c0593521ed34d9990e8 # v6.0.1
        with:
          persist-credentials: false
          token: ${{ steps.app-token.outputs.token }}

      - name: Run Renovate
        uses: renovatebot/github-action@f7fad228a053c69a98e24f8e4f6cf40db8f61e08 # v44.2.1
        env:
          LOG_LEVEL: ${{ inputs.logLevel || 'debug' }}
          RENOVATE_AUTODISCOVER: true
          RENOVATE_AUTODISCOVER_FILTER: ${{ github.repository }}
          RENOVATE_DRY_RUN: ${{ inputs.dryRun }}
          RENOVATE_INTERNAL_CHECKS_FILTER: strict
          RENOVATE_PLATFORM: github
          RENOVATE_PLATFORM_COMMIT: true
        with:
          token: ${{ steps.app-token.outputs.token }}
          renovate-version: ${{ inputs.version || 'latest' }}
```

---

## 配置修改

`.renovaterc.json5` 移除 schedule 配置：

```diff
  extends: [
    // ... 保持不变
  ],
  dependencyDashboard: true,
  dependencyDashboardTitle: "Renovate Dashboard 🤖",
- schedule: ["every weekend"],
  ignorePaths: ["**/*.sops.*"],
```

---

## 清理 Mend 托管

迁移完成后，从 Mend 平台取消托管：

1. 访问 https://developer.mend.io/
2. 找到 `shelken/home-ops` 仓库
3. 移除或禁用该仓库的 Renovate 托管

---

## 迁移步骤

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 更新 GitHub App 权限 | 添加 Contents、Issues、Workflows 写权限 |
| 2 | 重新授权 App | 在仓库安装设置中确认新权限 |
| 3 | 创建 workflow 文件 | 添加 `.github/workflows/renovate.yaml` |
| 4 | 修改 renovate 配置 | 移除 `.renovaterc.json5` 中的 schedule |
| 5 | 提交并推送 | 推送到 main 分支 |
| 6 | 验证运行 | 手动触发 workflow 验证是否正常 |
| 7 | 清理 Mend | 从 Mend 平台移除仓库托管 |

---

## 参考

- [onedr0p/home-ops renovate workflow](https://github.com/onedr0p/home-ops/blob/main/.github/workflows/renovate.yaml)
- [Renovate GitHub Action](https://github.com/renovatebot/github-action)
