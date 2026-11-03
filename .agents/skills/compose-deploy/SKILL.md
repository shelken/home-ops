---
name: compose-deploy
description: Use when 部署/更新 sakamoto 的 Compose 服务
---

# Compose Deploy (sakamoto)

## Overview

在 home-ops 仓库中部署或更新 sakamoto 的 Docker Compose 服务。进入仓库后 mise 自动加载运行环境，直接执行对应 Task

VPS 的业务容器不在本仓库：它们由 nix-config 的 `hosts/vps/vps-cc/apps/` 以 NixOS 的 `virtualisation.oci-containers` 声明，部署走那边的 `just deploy vps-cc`

## When to Use

- 部署或更新 sakamoto 的 Compose 服务
- 仅同步配置文件（不重启容器）
- 查看 sakamoto Compose 服务运行日志与状态
- 遇到 `task: command not found` 时自举依赖

**When NOT to use**

- 部署或更新 VPS 容器（去 nix-config，读那边的 `docs/user-guide/06-containers.md`）
- 操作 K8s、Flux 或 Ansible 时

## Core Pattern

```bash
cd {home-ops-dir}
task compose:deploy:sakamoto
```

## Quick Reference

| 目的            | 命令                           |
| --------------- | ------------------------------ |
| 部署 sakamoto   | `task compose:deploy:sakamoto` |
| 仅同步配置      | `task compose:sync:sakamoto`   |
| 查看日志        | `task compose:logs:sakamoto`   |
| 查看状态        | `task compose:status:sakamoto` |

> 需要强制重建容器时：在 deploy 命令后追加 `-- --force-recreate`

## Implementation

1. 进入仓库根目录：`cd {home-ops-dir}`（mise 自动加载）
2. 首次使用先 `mise trust && mise install && mise run setup`
3. 按 Quick Reference 执行对应 task

## Common Mistakes

- 未在仓库根目录执行导致找不到 Taskfile 或环境未加载
- 仅需同步配置时误用 deploy 造成非必要重启
