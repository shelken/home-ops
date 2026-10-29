---
name: compose-deploy
description: Use when 部署/更新 VPS 或 sakamoto
---

# Compose Deploy (VPS / sakamoto)

## Overview

在 home-ops 仓库中部署或更新 VPS 与 sakamoto 的 Docker Compose 服务。进入仓库后 mise 自动加载运行环境，直接执行对应 Task

## When to Use

- 部署或更新 VPS 与 sakamoto 的 Compose 服务
- 仅同步配置文件（不重启容器）
- 查看 Compose 服务运行日志与状态
- 遇到 `task: command not found` 时自举依赖

**When NOT to use**

- 操作 K8s、Flux 或 Ansible 时
- 执行非 Compose 相关运维任务时

## Core Pattern

```bash
cd {home-ops-dir}
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

1. 进入仓库根目录：`cd {home-ops-dir}`（mise 自动加载）
2. 首次使用先 `mise trust && mise install && mise run setup`
3. 按 Quick Reference 执行对应 task

## Common Mistakes

- 未在仓库根目录执行导致找不到 Taskfile 或环境未加载
- 仅需同步配置时误用 deploy 造成非必要重启
