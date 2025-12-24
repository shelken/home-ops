<!--
================================================================================
SYNC IMPACT REPORT
================================================================================
Version Change: N/A → 1.0.0 (Initial Release)

Modified Principles: N/A (initial version)

Added Sections:
  - Core Principles (5 principles)
  - Technology Stack
  - Development Workflow
  - Governance

Removed Sections: N/A (initial version)

Templates Requiring Updates:
  - .specify/templates/plan-template.md      ✅ No changes needed (generic)
  - .specify/templates/spec-template.md      ✅ No changes needed (generic)
  - .specify/templates/tasks-template.md     ✅ No changes needed (generic)
  - .specify/templates/commands/*.md         ⚠ Directory not found

Deferred Items: None
================================================================================
-->

# home-ops Constitution

## Core Principles

### I. GitOps 优先

所有集群变更 **必须** 通过 Git 提交实现，由 Flux CD 自动同步至集群。

- 禁止直接对集群进行 `kubectl apply` 或手动修改
- 所有配置变更必须经过 Pull Request 审查
- 集群状态必须与 Git 仓库保持一致
- 紧急修复也必须先提交 Git，再由 Flux 同步

**理由**：确保变更可追溯、可回滚，避免配置漂移，维护单一真实来源。

### II. 声明式配置

使用 YAML 声明期望状态，避免命令式操作。

- 使用 Kustomize 和 HelmRelease 管理资源
- 所有服务配置必须可重复部署
- 禁止在 Pod 内部进行持久化配置修改
- 优先使用 Kubernetes 原生资源，避免自定义脚本

**理由**：声明式配置使系统状态可预测、可审计，便于灾难恢复。

### III. 资源效率

注意资源限制，适配异构节点（包括低功耗设备）。

- 所有 Deployment **必须** 设置资源 requests 和 limits
- 轻量级负载优先调度至低功耗节点（tvbox）
- 合理使用 nodeSelector、tolerations 和 affinity
- 避免资源浪费，定期审查资源使用情况

**理由**：homelab 资源有限，需高效利用各节点能力，降低能耗。

### IV. 简单性

KISS (Keep It Simple, Stupid)，避免过度工程。

- 优先使用现有成熟方案，避免重复造轮子
- 配置应尽可能简洁，删除不必要的复杂性
- 新增组件必须有明确的需求和价值
- 避免为假设性需求提前设计

**理由**：简单的系统更易于维护、调试和迭代。

### V. 中文沟通

文档、注释和交互优先使用中文。

- README、CLAUDE.md 等项目文档使用中文
- Git commit body 使用中文（title 可用英文遵循 Conventional Commits）
- 代码注释涉及业务逻辑时使用中文
- AI 助手交互使用中文

**理由**：提高本地化可读性，降低理解成本。

## Technology Stack

本项目使用以下核心技术栈，变更需经过评审：

| 类别 | 技术 | 用途 |
|------|------|------|
| 容器编排 | Kubernetes (k3s) | 轻量级 Kubernetes 发行版 |
| GitOps | Flux CD v2 | 持续部署和同步 |
| 网络 | Cilium, Multus | eBPF 网络、多网卡支持 |
| 网关 | Envoy Gateway | 入口流量管理 |
| 密钥管理 | SOPS + External-Secrets | 密钥加密和同步 |
| 存储 | Longhorn | 分布式块存储 |
| 数据库 | CloudNative-PG | PostgreSQL Operator |
| 监控 | Prometheus, Grafana | 指标采集和可视化 |

## Development Workflow

### 变更流程

1. 创建功能分支 (`feature/xxx` 或 `fix/xxx`)
2. 本地验证 YAML 语法 (`yamllint`)
3. 提交 Pull Request，等待 CI 检查
4. 合并至 main，Flux 自动同步
5. 验证集群状态

### 命名规范

- Namespace: 小写，使用连字符分隔 (例: `media`, `home-automation`)
- HelmRelease: 与应用名一致
- ConfigMap/Secret: `<app>-<purpose>` (例: `plex-config`)

### 测试验证

- 使用 `flux diff` 预览变更
- 使用 `kubectl diff` 对比资源差异
- 部署前在 staging 环境验证（如适用）

## Governance

### 修订流程

1. Constitution 变更必须通过 Pull Request
2. 变更需在 PR 描述中说明理由
3. 版本号遵循语义化版本规范：
   - MAJOR: 原则删除或重新定义（不兼容变更）
   - MINOR: 新增原则或重大扩展
   - PATCH: 措辞修正、澄清

### 合规检查

- 每次 PR 审查应验证是否符合 Constitution 原则
- 复杂度增加需在 PR 中明确说明理由
- 参考 `CLAUDE.md` 获取运行时开发指引

### 优先级

Constitution 原则优先于其他开发实践。当存在冲突时，按以下顺序决策：

1. Constitution 原则
2. CLAUDE.md 项目指引
3. 通用最佳实践

**Version**: 1.0.0 | **Ratified**: 2025-12-24 | **Last Amended**: 2025-12-24
