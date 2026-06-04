# AIstudioProxyAPI headless 镜像与常驻服务设计

## 背景

目标是在 homelab 中部署 AIstudioProxyAPI，让它以 headless 模式运行，并在集群内提供 OpenAI-compatible API。服务只作为后续 CPA 的 upstream，本次不改 CPA 配置，也不设计模型别名。

AIstudioProxyAPI 使用 FastAPI、Playwright、Camoufox，把 Google AI Studio 网页能力转成 OpenAI-compatible API。首次 Google 登录仍在本地完成，生成的浏览器认证状态再放入集群 PVC。

## 本次范围

包含：

- 在 `containers` 仓库新增 `apps/aistudio-proxy-api/` 镜像构建配置。
- 从 upstream `CJackHwang/AIstudioProxyAPI` 的 release/tag 构建镜像。
- 产出 `ghcr.io/<GHCR_OWNER>/aistudio-proxy-api:<VERSION>`。
- 在 `home-ops` 中新增 `k8s/apps/common/aistudio-proxy-api/app/`。
- 部署一个 headless 常驻服务。
- 使用 PVC 保存 `auth_profiles`，并通过现有备份体系保护。
- 服务只暴露 ClusterIP。

不包含：

- login 镜像。
- `aistudio-proxy-api/login/` 服务。
- noVNC、KasmVNC、Xvfb Web 登录入口。
- external Route、internal Route、LoadBalancer。
- CPA provider 配置。
- 模型 alias 设计。

后续如果需要集群内网页登录入口，再在同一个应用目录下新增 `login/`，并由同级 `ks.yaml` 引用 `app/` 与 `login/`。

## 架构

运行链路：

```text
本地 debug 登录
  -> 生成 auth_profiles
  -> auth_profiles 放入集群 PVC
  -> aistudio-proxy-api Pod 挂载 PVC
  -> headless Camoufox/Playwright 访问 Google AI Studio
  -> FastAPI 提供 OpenAI-compatible API
  -> 后续 CPA 通过 ClusterIP 调用
```

集群内预留地址：

```text
http://aistudio-proxy-api.default.svc.cluster.local:2048/v1
```

该地址仅用于后续 CPA 设计参考。本次不修改 CPA。

## 镜像设计

第一版采用保守构建方式，重点验证 headless 可用性。优化镜像体积和只读 rootfs 放到后续阶段。

镜像目录：

```text
apps/aistudio-proxy-api/
  Dockerfile
  docker-bake.hcl
```

`docker-bake.hcl` 跟踪 upstream release：

```hcl
variable "VERSION" {
  // renovate: datasource=github-releases depName=CJackHwang/AIstudioProxyAPI
  default = "<VERSION>"
}

variable "SOURCE" {
  default = "https://github.com/CJackHwang/AIstudioProxyAPI"
}
```

Dockerfile 使用多阶段构建：

```text
builder:
  - 基于 Python slim 镜像
  - 拉取 upstream release/tag
  - 临时安装 Poetry
  - 使用 upstream 的 pyproject.toml 与 poetry.lock 安装 runtime 依赖

runtime:
  - 基于 Python slim 镜像
  - 安装 Camoufox/Playwright 所需系统库
  - 复制应用代码和依赖
  - 准备浏览器资源
  - 创建非 root 用户
  - 默认以 headless 模式启动
```

Poetry 只存在于 builder。runtime 镜像不带 Poetry，也不带构建工具。

暂不改用 uv。原因是 upstream 当前提供 `poetry.lock`，没有 `uv.lock`。第一版使用 upstream 的依赖锁，可以减少依赖解析差异。等服务验证可用后，再评估是否在 `containers` 仓库维护 `uv.lock`。

默认启动命令：

```text
python launch_camoufox.py --headless --server-port 2048 --stream-port 3120 --helper ''
```

优先使用单进程启动方式。只有验证发现 upstream 需要 supervisor 协调时，才保留 supervisor。

镜像不包含：

- auth JSON。
- noVNC / KasmVNC。
- Web 桌面组件。
- 登录专用工具链。

## Kubernetes 资源设计

目录：

```text
k8s/apps/common/aistudio-proxy-api/
  ks.yaml
  app/
    kustomization.yaml
    helmrelease.yaml
```

`ks.yaml` 只引用 `app/`：

```text
path: ./k8s/apps/common/aistudio-proxy-api/app
```

依赖：

- cilium
- volsync
- 如配置需要 ExternalSecret，再依赖 azure-store / external-secrets

服务形态：

```text
Service type: ClusterIP
HTTPRoute: 无
LoadBalancer: 无
Ingress: 无
```

端口：

```text
2048  主 API
3120  stream proxy，后续可配置为 0 关闭
```

## 存储设计

认证状态使用 PVC，挂载到：

```text
/app/auth_profiles
```

目录结构沿用 upstream：

```text
/app/auth_profiles/active/
/app/auth_profiles/saved/
/app/auth_profiles/emergency/
```

只备份认证状态，不备份浏览器缓存与日志。

建议临时目录：

```text
/tmp                    emptyDir
/app/logs               emptyDir
/app/.cache             emptyDir
/home/app/.cache        emptyDir
/dev/shm                memory emptyDir
```

`/dev/shm` 初始可配置为 512Mi。如浏览器运行异常，再按观测结果调整。

## 配置

第一版使用环境变量，不引入复杂模板。

建议配置：

```text
SERVER_PORT=2048
DEFAULT_FASTAPI_PORT=2048
STREAM_PORT=3120
LAUNCH_MODE=headless
AUTO_SAVE_AUTH=false
AUTO_ROTATE_AUTH_PROFILE=true
COOKIE_REFRESH_ENABLED=true
COOKIE_REFRESH_ON_REQUEST_ENABLED=true
COOKIE_REFRESH_ON_SHUTDOWN=true
SERVER_LOG_LEVEL=INFO
DEBUG_LOGS_ENABLED=false
TRACE_LOGS_ENABLED=false
```

代理相关配置如包含私有地址，应通过 Secret 注入：

```text
UNIFIED_PROXY_CONFIG
NO_PROXY
```

公开 YAML 和公开文档不写真实域名、IP、主机名、用户名、密钥路径或私有 URL。

## auth SOP

本阶段不做集群内登录。

本地生成认证状态：

```bash
python launch_camoufox.py \
  --debug \
  --auto-save-auth \
  --save-auth-as <PROFILE_NAME> \
  --exit-on-auth-save
```

生成后准备：

```text
1. 确认 auth_profiles/saved/<PROFILE_NAME>.json 存在。
2. 将可用 profile 复制到 auth_profiles/active/。
3. 将 auth_profiles 放入集群 PVC。
4. 启动 aistudio-proxy-api。
```

auth 文件属于运行态数据，不提交到 Git，也不写入镜像。

生产容器启用 cookie refresh。服务运行期间，认证状态可能被更新并保存到 PVC。这也是使用 PVC + 备份，而不是 SOPS Secret 的原因。

## 安全设计

基础 Pod 安全配置：

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch
```

容器安全配置：

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

`readOnlyRootFilesystem` 第一版先不启用。Playwright/Camoufox 的可写路径较多，先确认目录后再收紧。

服务没有对外入口。只有集群内 Service 可访问。

## 错误处理

服务启动前必须已有：

```text
/app/auth_profiles/active/*.json
```

如果没有可用 auth，容器应失败，并通过日志暴露问题。不要创建空 auth，也不要静默改用其他目录。

第一版只验证单个 active profile。不设计自动 profile 选择逻辑。

## 资源建议

初始资源：

```yaml
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    memory: 2Gi
```

浏览器类容器对内存和 `/dev/shm` 敏感。资源值以验证结果为准。

## 健康检查

使用 upstream 健康接口：

```text
GET /health
```

readiness 建议：

```text
initialDelaySeconds: 30
periodSeconds: 10
timeoutSeconds: 3
failureThreshold: 12
```

liveness 建议：

```text
initialDelaySeconds: 120
periodSeconds: 30
timeoutSeconds: 5
failureThreshold: 6
```

## 验证计划

镜像侧：

```text
1. 构建本地镜像。
2. 挂载本地 auth_profiles。
3. 启动 headless 服务。
4. 请求 /health。
5. 请求 /v1/models。
```

Kubernetes 侧：

```text
1. Flux 创建 aistudio-proxy-api/app。
2. Pod 成功启动。
3. Service 类型为 ClusterIP。
4. 无 Route、Ingress、LoadBalancer。
5. 从集群内访问 /health。
6. 从集群内访问 /v1/models。
```

数据侧：

```text
1. active auth 存在。
2. saved auth 存在。
3. cookie refresh 后 auth_profiles 有更新时间变化。
4. 备份只覆盖 auth_profiles PVC。
```

安全侧：

```text
1. 容器 UID 非 0。
2. Linux capabilities 已移除。
3. 未允许提权。
4. 镜像不包含 auth 文件。
5. 服务没有对外暴露。
```

## 后续方向

服务稳定使用一段时间后，再评估：

- login 镜像。
- `aistudio-proxy-api/login/`。
- 集群内 Web 登录入口。
- 使用 uv 与自维护 `uv.lock` 优化构建。
- 启用 `readOnlyRootFilesystem`。
- 关闭 stream proxy。
- CPA provider 与模型 alias 设计。

## 依据

- Kubernetes Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Docker multi-stage builds: https://docs.docker.com/get-started/docker-concepts/building-images/multi-stage-builds/
- Docker image build best practices: https://docs.docker.com/get-started/workshop/09_image_best/
- Poetry documentation: https://python-poetry.org/docs/
- uv Docker integration: https://docs.astral.sh/uv/guides/integration/docker/
- AIstudioProxyAPI upstream: https://github.com/CJackHwang/AIstudioProxyAPI
