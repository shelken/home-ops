---
name: simple-service-app
description: 在 containers 仓库创建无后端轻量前端应用，并串起 home-ops GitOps 部署流程。Use when 用户要求创建简单应用、轻量前端服务、小工具、展示页、SPA、simple-service，或提到“复制模板到 apps 并部署”。
---

# Simple Service App

## 触发场景

用户要求创建无后端、单一目的的前端应用时使用本 skill，例如：

- “创建一个 xxx 应用”
- “做一个简单工具/展示页/SPA”
- “用 simple-service 模板部署一个服务”

如果需求包含后端 API、数据库、PVC、复杂认证或长期状态存储，先指出它不属于 simple-service，再确认是否仍按轻量前端服务处理。

## 总流程

1. 在 `containers` 仓库复制模板到 `apps/<service-name>/`。
2. 清理模板占位内容，只保留当前服务需要的代码、文案和配置。
3. 本地验证：npm build、Docker build、Docker 预览/health check。
4. 提交并推送 `containers`，等待 CI 产出镜像。
5. 在 `home-ops` 的 `k8s/apps/common/simple-service/<service-name>/` 添加 GitOps 部署资源。
6. 在 `k8s/apps/common/simple-service/ks.yaml` 注册该服务。
7. 运行 kustomize 渲染验证；不直接操作集群。

## containers 创建步骤

在 `containers` 仓库根目录：

```bash
cp -r templates/simple-service apps/<service-name>
```

随后必须更新：

- `apps/<service-name>/docker-bake.hcl`：`APP` 改为 `<service-name>`。
- `apps/<service-name>/package.json`：`name` 改为 `<service-name>`。
- `apps/<service-name>/index.html`：更新 `<title>` 和 meta description。
- `apps/<service-name>/src/App.tsx`：删除 starter UI，替换为当前服务界面。
- `apps/<service-name>/AGENTS.md`：删除模板创建流程等临时内容，只保留该服务长期规则。

## containers 本地验证

在 `apps/<service-name>/`：

```bash
npm ci
npm run build
npm run docker:build
npm run docker:run
```

`docker:run` 用于本地预览页面，默认监听：

```text
http://127.0.0.1:18080
```

需要快速 health/SPA fallback 验证时运行：

```bash
npm run docker:smoke
```

## home-ops 部署步骤

在 `home-ops` 中新增：

```text
k8s/apps/common/simple-service/<service-name>/
├── kustomization.yaml
└── helmrelease.yaml
```

部署约定：

- 使用现有 `app-template` HelmRelease 模式。
- 镜像引用 `ghcr.io/<owner>/<service-name>:rolling` 或 CI 产出的固定 tag/digest。
- 容器端口使用模板 Nginx 的 `8080`。
- route hostname 使用独立子域名。
- 不需要后端、密钥、PVC 时，不创建无关资源。

在 `k8s/apps/common/simple-service/ks.yaml` 追加一个 Flux `Kustomization`，`path` 指向该服务目录。

验证：

```bash
kustomize build k8s/apps/common/simple-service/<service-name>
kustomize build k8s/apps/common
kustomize build k8s/apps/staging
```

## GitOps 边界

- 不执行 `kubectl apply`。
- 不直接修改集群状态。
- 本地代码未提交/未推送不等于集群状态。
- 删除资源前必须让用户确认。
