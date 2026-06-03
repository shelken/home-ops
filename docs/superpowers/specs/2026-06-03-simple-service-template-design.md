# simple-service 快速前端服务模板设计

## 背景

需要固定一条从 idea 到集群上线的轻量工作流，用于实现无后端、功能单一的前端服务。服务可能是展示页，也可能是查询、转换、生成器、小计算器等简单工具。源码和容器构建放在 `containers` 仓库；集群部署通过 `home-ops` 的 Flux GitOps 管理。

## 目标

- 新服务能从统一模板快速创建。
- 每个服务独立构建成容器镜像。
- `home-ops` 只引用镜像和路由，不存放大量前端源码。
- 集群部署遵循 Flux GitOps，不直接操作集群。
- DNS 通过已配置的 External-DNS 自动管理。
- 模板足够轻，不为所有服务预装复杂组件库。

## 非目标

- 不设计后端 API 或数据库。
- 不把多个服务塞进同一个镜像。
- 不修改现有 `containers` CI 主流程。
- 不在 `home-ops` 中托管前端源码。
- 不预装 `@base-ui/react`。

## containers 仓库结构

`containers` 仓库保留现有 `apps/<app>/` 构建模型。模板放在 `templates/`，避免被 `apps/` 变更检测误当作真实应用构建。

```text
containers/
├── templates/
│   └── simple-service/
│       ├── AGENTS.md
│       ├── Dockerfile
│       ├── docker-bake.hcl
│       ├── nginx.conf
│       ├── package.json
│       ├── vite.config.ts
│       ├── tsconfig.json
│       ├── index.html
│       └── src/
└── apps/
    ├── service-a/
    ├── service-b/
    └── service-c/
```

新服务创建流程：

```bash
cp -r templates/simple-service apps/<service-name>
```

随后修改 `docker-bake.hcl` 的应用名、`package.json` 项目名、`index.html` 标题和 `src/` 业务内容。

## 前端模板技术栈

- React + Vite + TypeScript。
- Tailwind CSS v4 用于快速样式开发。
- 不默认安装 Base UI。
- 模板内 `AGENTS.md` 记录：当服务需要 Dialog、Menu、Select、Form、Toast 等复杂交互组件时，再引入 `@base-ui/react`，并优先查阅 `https://base-ui.com/llms.txt`。

这个选择保持默认模板轻量，同时为 agent 开发复杂交互留出明确路径。

## 容器封装

每个服务使用相同的多阶段构建模式：

```text
Node builder → Vite build → Nginx Alpine runtime
```

Nginx 在 Pod 内负责：

- 监听 HTTP 端口。
- 服务静态构建产物。
- 为 SPA 路由提供 fallback：`try_files $uri /index.html`。
- 为 hash 资源设置长缓存。
- 按需启用 gzip。

Envoy Gateway 只负责集群入口路由、TLS 终结等网关职责，不能替代 Pod 内的静态文件服务。

## CI/CD 流程

现有 `containers` CI 已按 `apps/` 子目录检测变更并构建镜像。新服务放入 `apps/<service-name>/` 后可直接复用现有流程：

```text
push apps/<service-name>/
→ GitHub Actions 检测变更目录
→ 构建 ghcr.io/<owner>/<service-name>:rolling
→ 推送镜像
```

不需要修改现有 workflow。模板目录在 `templates/` 下，不参与应用构建。

## home-ops 部署结构

所有简单服务集中在 `simple-service` 总目录下，避免 `k8s/apps/common/` 一级目录膨胀。每个子目录代表一个独立服务，`ks.yaml` 集中引用所有相关服务。

```text
k8s/apps/common/simple-service/
├── ks.yaml
├── service-a/
│   ├── kustomization.yaml
│   └── helmrelease.yaml
├── service-b/
│   ├── kustomization.yaml
│   └── helmrelease.yaml
└── service-c/
    ├── kustomization.yaml
    └── helmrelease.yaml
```

上层只注册一次：

```text
k8s/apps/common/kustomization.yaml
└── ./simple-service/ks.yaml
```

`simple-service/ks.yaml` 内为每个服务维护一个 Flux `Kustomization`，分别指向对应子目录：

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: service-a
  namespace: default
spec:
  targetNamespace: default
  path: ./k8s/apps/common/simple-service/service-a
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  interval: 1h
  retryInterval: 2m
  timeout: 5m
  wait: false
```

每个服务子目录内使用现有 `app-template` 模式部署容器镜像，并配置 Envoy Gateway route。

## 路由与 DNS

每个服务使用独立子域名：

```text
<service-name>.<domain>
```

`helmrelease.yaml` 中声明对应 hostname。External-DNS 已配置，DNS 记录由集群自动管理，不需要手动改 DNS。

## 错误处理与边界

- 镜像构建失败由 GitHub Actions 暴露，不在集群侧兜底。
- 服务不需要数据库、密钥、PVC 时，不创建 `externalsecret.yaml`、PVC 或无关依赖。
- Nginx fallback 只处理前端路由；不存在的静态资源仍应返回实际 404，避免掩盖资源路径错误。
- 每个服务独立镜像、独立 Flux Kustomization，避免一个服务变更影响其他服务。

## 验证策略

containers 侧：

```bash
npm run build
docker build -t <service-name>:local .
```

home-ops 侧：

```bash
kustomize build k8s/apps/common/simple-service/<service-name>
kustomize build k8s/apps/common
kustomize build k8s/apps/staging
```

CI 侧验证：

- GitHub Actions 成功构建并推送镜像。
- `home-ops` 渲染通过后由 Flux 自动部署。

## 成功标准

- 新服务可通过复制模板在短时间内启动开发。
- 推送 `containers/apps/<service-name>/` 后自动生成容器镜像。
- `home-ops` 只需新增 `simple-service/<service-name>/` 子目录和 `ks.yaml` 引用。
- 服务通过子域名访问。
- 模板保持轻量，复杂交互按需引入 Base UI。
