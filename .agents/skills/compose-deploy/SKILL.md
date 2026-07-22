---
name: compose-deploy
description: Use when 部署/更新 VPS 或 sakamoto
---

# Compose Deploy (VPS / sakamoto)

## Overview

在 home-ops 仓库里部署或更新 VPS / sakamoto 的 docker
compose，进入仓库后 mise 会自动加载工具环境，直接执行 task。

## When to Use

- 需要部署/更新 VPS 或 sakamoto 的 compose 服务
- 需要仅同步配置（不重启容器）
- 需要查看 compose 日志/状态
- 看到 `task: command not found`

**When NOT to use**

- 操作 k8s/flux/ansible 时
- 不是 compose 相关任务时

## Core Pattern

```bash
cd ~/Code/MyRepo/home-ops
task compose:deploy:vps
```

## Quick Reference

| 目的                 | 命令                            |
| -------------------- | ------------------------------- |
| 部署 VPS             | `task compose:deploy:vps`       |
| 部署 sakamoto        | `task compose:deploy:sakamoto`  |
| 仅同步 VPS 配置      | `task compose:sync:vps`         |
| 仅同步 sakamoto 配置 | `task compose:sync:sakamoto`    |
| VPS 日志             | `task compose:logs:vps`         |
| VPS 状态             | `task compose:status:vps`       |
| sakamoto 日志        | `task compose:logs:sakamoto`    |
| sakamoto 状态        | `task compose:status:sakamoto`  |

> 需要强制重建容器时：在 deploy 命令后追加 `-- --force-recreate`

## Implementation

1. 进入仓库根目录：`cd ~/Code/MyRepo/home-ops`（mise 自动加载）
2. 首次使用先 `mise trust && mise install && mise run setup`
3. 按 Quick Reference 执行对应 task

## Common Mistakes

- 不在仓库根目录执行 → 找不到 Taskfile / 工具未加载
- 只需要同步却用 deploy → 不必要的重启
