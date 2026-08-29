---
name: authelia-integration
description: 在 home-ops 中为服务接入 Authelia。Use when 服务无原生 SSO 需网关 extAuth、服务支持声明式 OIDC、或将已有 components/authelia 迁移到应用原生 OIDC。
---

# Authelia 接入 SOP

## 目标

按服务能力只选一条路径：

```text
服务需要认证
├─ 不支持原生 SSO → A. 网关 extAuth
├─ 支持声明式 OIDC，当前无网关 extAuth → B. 原生 OIDC
└─ 支持声明式 OIDC，当前已有网关 extAuth → C. 迁移到原生 OIDC
```

声明式 OIDC 指 client ID、client secret、issuer、callback 等配置可由环境变量或受 Git 管理的配置文件注入

开始前读取：

- `docs/ARCHITECTURE.md`，确认 Flux 的 infra → apps 顺序
- `.taskfile/secret.yaml`，使用现有密钥 task
- `k8s/infra/common/security/authelia/app/configuration.yaml`，参考相同协议客户端
- 目标服务的 `ks.yaml`、Route、ExternalSecret 与上游 OIDC 文档

## 共同调查

1. 确认服务是否原生支持 OIDC/OAuth2，优先查上游当前文档
2. 记录 callback URI、scopes、token endpoint auth method、PKCE、grant type、response type
3. 确认配置可声明式注入，要求重启后仍可复现
4. 找一个协议行为最接近的现有 client，当字段参考，不复制无依据字段

完成标准：每个 Authelia client 字段都能对应上游要求，尤其是 `token_endpoint_auth_method`

## A. 服务不支持原生 SSO

在目标 `ks.yaml` 的 `spec` 中引入组件：

```yaml
components:
  - ../../../../components/authelia
postBuild:
  substitute:
    APP: <app>
```

路径深度按目标目录调整，默认组件以 `${APP}` 查找同名 HTTPRoute，Route 名不同则补充：

```yaml
postBuild:
  substitute:
    APP: <app>
    AUTHELIA_ROUTE: <route-name>
```

检查 `k8s/components/authelia/securitypolicy.yaml` 获取当前行为，不在 skill 复制策略细节

如果外部健康检查也经过该 Route：

- 优先使用 `configuration.yaml` 已统一放行的健康路径
- 仅在真实探测路径未覆盖时，为准确域名和准确路径增加最小 bypass
- 保持业务路径由 extAuth 保护

完成标准：渲染结果存在目标 Route 对应的 `SecurityPolicy`，未认证业务请求被拦截，健康检查仍成功

## B. 全新接入原生 OIDC

### 1. 注册 Authelia client

在 `identity_providers.oidc.clients` 增加最小 client：

```yaml
- client_id: "<app>"
  client_name: "<display-name>"
  client_secret: ""
  public: false
  authorization_policy: "two_factor"
  pre_configured_consent_duration: 1y
  redirect_uris:
    - "https://<subdomain>.${MAIN_DOMAIN}/<callback>"
  scopes: ["openid", "profile", "email"]
  response_types: ["code"]
  grant_types: ["authorization_code"]
  token_endpoint_auth_method: "<method-required-by-app>"
```

只保留应用明确需要的字段，`token_endpoint_auth_method` 必须来自应用文档或运行证据，不能从相邻 client 猜测

### 2. 生成并写入 OIDC 密钥

Client Secret 明文只进入应用对应的 Azure Key Vault JSON secret，Argon2 digest 可提交到 Authelia 配置

先保持新 client 的 `client_secret: ""`，再执行一次初始化 task：

```bash
task secret:init-authelia-oidc-client \
  secret="<azure-json-secret>" \
  key="<APP>_OIDC_CLIENT_SECRET" \
  client="<app>"
```

该 task 从 Authelia HelmRelease 读取当前固定镜像版本，在 shell 内一次生成明文与 digest，使用 `secret:set-key` 写入明文，并按唯一 `client_id` 定点设置 digest，它只接受空的 `client_secret`，重复执行会失败，避免误触发在线密钥轮换

agent 对 Key Vault 只使用 `secret:init-authelia-oidc-client`、`secret:set-key` 与 `secret:keys`：

```bash
task secret:keys secret="<azure-json-secret>"
```

应用另需 session/cookie 签名密钥时，以同一闭环直接写入：

```bash
set -euo pipefail
kv_secret="<azure-json-secret>"
session_key="<APP>_AUTH_SECRET"
session_secret=$(openssl rand -hex 64)
task secret:set-key \
  secret="$kv_secret" \
  key="$session_key" \
  value="$session_secret" >/dev/null
unset session_secret
printf 'session secret stored\n'
```

敏感值始终停留在 shell 与 Key Vault 中，工具调用文本、工具输出、提交、日志和回复只出现 key 名

### 3. 注入应用

在应用现有 `ExternalSecret` 中映射实际消费的 key，并通过 `envFrom` 或明确的 env 引用注入，一个 target Secret 只由一个 ExternalSecret 管理

非敏感项写入 HelmRelease 或受 Git 管理的配置，例如：

- OIDC issuer
- client ID
- callback/external URL
- scopes
- 启用认证的开关

完成标准：Pod 环境中存在所需 key 名，Git 与渲染输出没有明文 secret

## C. 从网关 extAuth 迁移到原生 OIDC

先完整执行 B，再清理旧链路：

1. 从目标 `ks.yaml` 删除 `components/authelia`
2. 删除只为该服务 extAuth 健康检查添加的 Authelia `access_control` bypass
3. 保留应用原生认证明确豁免的健康路径
4. 渲染确认旧 `SecurityPolicy` 已从期望状态消失
5. 部署后确认 Flux prune 已删除集群中的旧 `SecurityPolicy`

迁移期间不保留双层认证，一个入口只由应用原生 OIDC 负责登录流程

完成标准：业务请求直接进入应用登录流程，集群中无该服务旧 extAuth `SecurityPolicy`，健康检查正常

## 验证与部署

提交前：

```bash
kustomize build <app-dir>
kustomize build k8s/infra/staging
kustomize build k8s/apps/staging
pre-commit run --files <modified-files>
```

部署严格按顺序：

1. push 后先让 `flux-system/infra` 与 Authelia Ready
2. 确认 Authelia rollout 成功且新日志无 client 配置错误
3. 再同步 apps，确认目标 ExternalSecret、HelmRelease 与 Pod Ready
4. A 路径确认 `SecurityPolicy` 存在，B/C 路径确认不存在
5. 验证健康端点
6. 由浏览器完成一次真实登录与退出，期间同时观察应用和 Authelia 日志

OIDC 回调失败时，先对照双方日志中的实际认证方式，出现 `client authentication failed` 时，核对 `token_endpoint_auth_method`，修改 Authelia client 与应用真实行为一致的值

## 交付检查

- 已明确选择 A、B 或 C
- callback、scope、PKCE 和 token 认证方式均有上游依据或运行证据
- agent 未读取或输出 secret value
- OIDC client 使用 `task secret:init-authelia-oidc-client` 初始化，其他密钥使用 `task secret:set-key` 写入，用 `task secret:keys` 验证 key 名
- Authelia digest 与应用明文 Client Secret 来自同一次生成
- ExternalSecret 只暴露应用实际消费的 key
- infra Ready 后才处理 apps
- 浏览器登录、退出与健康检查均通过

## 官方参考

- [Authelia OpenID Connect clients](https://www.authelia.com/configuration/identity-providers/openid-connect/clients/)
- [Authelia 生成安全值](https://www.authelia.com/reference/guides/generating-secure-values/)
