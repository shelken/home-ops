# Envoy Gateway 原生 OIDC 组件（备选）

本目录为 Envoy Gateway 原生 OIDC 的备选声明。

## 状态与决策

集群当前统一使用 `components/authelia`（extAuth 方案），不使用原生 OIDC，原因如下：

- 原生 OIDC 需要为每个受保护路由独立配置 Client ID 与 Client Secret，维护成本高
- 原生 OIDC 无法细粒度过滤无需保护的公开路径（如健康检查或公共静态资产）
