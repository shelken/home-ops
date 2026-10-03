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

## 集群外资产模块

集群外的东西按**功能**切，一个功能 = 一份声明 + 一个下发器 + 一个 task 命名空间 + 一篇文档。
`router/` 是照此摆的样板：

```
router/
├── bird/                  # 目录名 = task 命名空间后半段（task router:bgp:*）
│   ├── home.conf
│   └── mine.conf
└── dnsmasq/               # task router:dns:*
    ├── conf.d/            # 声明源，下发后等于路由器 /etc/dnsmasq.d
    ├── dnsmasq-int.hosts
    └── declare.py         # 只服务本功能的脚本放这里，不放 scripts/
```

- 只服务某一个功能的脚本、模板、数据，与它服务的声明同目录；跨功能复用的才进 `scripts/`
- 每份声明都要有对应的 `task <功能>:diff` 与 `:sync`：只读对比 → 展示差异 → 确认 → 下发。新配置沿用这套动作，不另造下发方式
- 一份声明的目录（`conf.d/`、`hosts` 之类）与它要落的远端路径一一对应，远端路径只在 taskfile 里定义一次
