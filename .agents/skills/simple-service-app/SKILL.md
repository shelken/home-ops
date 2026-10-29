---
name: simple-service-app
description: 在 containers 仓库创建无后端轻量前端应用，并串起 home-ops GitOps 部署流程。Use when 用户要求创建简单应用、轻量前端服务、小工具、展示页、SPA、simple-service，或提到“复制模板到 apps 并部署”。
---

# Simple Service App

## 触发场景

用户要求创建无后端、单一目的的前端应用时使用：轻量前端、小工具、展示页或 SPA

若需求包含后端 API、数据库、PVC、复杂认证或长期状态存储，应先提示超出 simple-service 范围，再按普通服务处理

## 总流程

1. 在 `containers` 仓库复制模板到 `apps/simple-<service-name>/`，应用名统一使用 `simple-` 前缀
2. 清理模板占位内容，仅保留当前服务必需的代码、文案与配置
3. 本地验证：执行 npm run build、Docker build 与本地健康检查
4. 启动本地 Docker 预览供人工确认，确认通过后再配置 home-ops
5. 提交并推送 `containers` 仓库，等待 CI 构建镜像并产出摘要
6. 在 `home-ops` 添加 GitOps 部署资源，注册到 `k8s/apps/common/simple-service/ks.yaml`，并确认 `k8s/apps/common/kustomization.yaml` 引用了 `simple-service/ks.yaml`（未引用时该组不会部署）
7. 运行 kustomize 渲染验证，产出访问地址：`https://simple-<service-name>.${MAIN_DOMAIN}`

## containers 创建步骤

```bash
cp -r templates/simple-service apps/simple-<service-name>
```

随后必须更新：

- `apps/simple-<service-name>/docker-bake.hcl`：`APP` 更新为 `simple-<service-name>`
- `apps/simple-<service-name>/package.json`：`name` 更新为 `simple-<service-name>`
- `apps/simple-<service-name>/index.html`：更新 `<title>` 与 meta description
- `apps/simple-<service-name>/src/App.tsx`：删除模板示例 UI，替换为实际业务界面
- `apps/simple-<service-name>/AGENTS.md`：删除模板初始化引导，仅保留长期维护规则

## containers 本地验证

在 `apps/simple-<service-name>/`：

```bash
npm ci
npm run build
npm run docker:build
npm run docker:smoke
```

启动给用户审阅的本地预览：

```bash
docker rm -f simple-<service-name>-preview >/dev/null 2>&1 || true
npm run docker:build
docker run --rm -d --name simple-<service-name>-preview -p 18080:8080 simple-<service-name>:local
curl -fsS http://127.0.0.1:18080/healthz
```

预览地址：`http://127.0.0.1:18080`

## home-ops 部署步骤

新增：

```text
k8s/apps/common/simple-service/simple-<service-name>/
├── kustomization.yaml
└── helmrelease.yaml
```

部署约定：

- 使用现有 `app-template` HelmRelease 模式
- 镜像版本使用 `docker-bake.hcl` 中的 semver，待 CI 产出 digest 后固定为 `semver@digest`，不使用 `rolling` 镜像
- 容器端口固定为模板 Nginx 的 `8080`
- route hostname 使用独立子域名
- 无后端、密钥或 PVC 需求时，严禁创建冗余资源
- Pod securityContext 沿用 common 规范：`runAsNonRoot: true`、`runAsUser/runAsGroup/fsGroup: 1000`、`fsGroupChangePolicy: OnRootMismatch`

验证：

```bash
kustomize build k8s/apps/common/simple-service/simple-<service-name>
kustomize build k8s/apps/common
kustomize build k8s/apps/staging
```
