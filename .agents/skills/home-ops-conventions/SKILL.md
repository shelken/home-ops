---
name: home-ops-conventions
description: shelken/home-ops 项目的目录结构与资源组织规范。在涉及该项目的文件放置、模块拆分、资源归属判断时使用。
---

# home-ops 项目规范

## 文件放置

**谁负责干这件事，相关文件就放谁那里。**

不看文件是什么类型，不看文件依赖哪个技术栈。只看这个文件是为谁服务的。

例：`zte-mifi-healer` 负责恢复外网连通性，它的告警规则就放在 `zte-mifi-healer/app/` 里，不管这条规则在技术上属于 Prometheus 还是 Gatus。

## Flux 目录结构

每个 app 固定两层：

```
<app-name>/
├── ks.yaml          # Flux 入口，被上层管理
└── app/             # 该 app 的所有资源
    ├── kustomization.yaml
    ├── helmrelease.yaml
    ├── externalsecret.yaml
    └── ...
```
