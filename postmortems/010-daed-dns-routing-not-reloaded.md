# daed dns routing rules lost at runtime, reload restores

**日期**: 2026-06-24
**影响**: 内部域名 `a.<INTERNAL_DOMAIN>` 经 daed 解析返回 NXDOMAIN。直查 OpenWrt DNS 正常。
**发现人**: shelken

## 问题

daed（旁路由）运行时 DNS routing 规则 `qname(suffix: <INTERNAL_DOMAIN>) -> router` 未生效，内部域名落入 `fallback: foreign` → Cloudflare DoH → NXDOMAIN。规则早已存在于 wing.db（多版本都有），但 daed 未在运行时加载。reload 后恢复正常。

## 现象

```bash
# 正确（直查路由器 OpenWrt DNS）
❯ dig @<ROUTER_IP> a.<INTERNAL_DOMAIN> A
# returns correct internal IP

# 失败（经 daed）
❯ dig @<TVBOX_IP> a.<INTERNAL_DOMAIN> A
# NXDOMAIN, authority: coco.ns.cloudflare.com

# reload 后恢复
❯ ssh root@<TVBOX_IP> "/etc/init.d/daed restart"
# dig 正常返回
```

## 根因

### 技术根因

**未确认。** daed 的 wing.db 中 `defaultdns` 的 DNS routing 配置包含 `qname(suffix: <INTERNAL_DOMAIN>) -> router`（版本 8、9 都有），但运行时未生效。reload 后恢复。

可能原因（均为推测）：
- daed 在特定条件下（启动时序/配置变更流程）未将 wing.db 中 DNS routing 规则正确编译到 dae 引擎
- daed 的 `procd_add_reload_trigger` 只监听 UCI 变更，wing.db 自身修改不触发热加载

### 排查错误

**错误 1：先答题，后取证。**
看到 `dig @旁路由` 返回 NXDOMAIN 直接说"daed 缺路由规则"，没先看配置。

**错误 2：凭记忆猜 MAC。**
断言 k8s 节点不在 MAC 白名单，实际就在列表里。

**错误 3：编造因果关系。**
看到 wing.db 里 `mode: "simple"` 就脑补"simple 模式忽略自定义 DNS 规则"，实际是 `users` 表的 UI 偏好字段。

**错误 4：版本号当根因。**
发现 `running_dns_version = 8 ≠ dns.version = 9` 就认定是版本落后。但规则很早就在版本 8 中了，版本差 1 只是冗余保存。版本号不符是表象不是原因。

**错误 5：未验证 daed 运行时实际加载的 DNS 规则。**
有 SQLite 数据库、有 `daed export` 命令，但没有用来确认运行时编译后的配置内容。

## 修复

```bash
ssh root@<TVBOX_IP> "/etc/init.d/daed restart"
# 或 daed Web UI 点 Apply
```

## 预防

1. 排查 daed 问题时优先查 `running_*_version` 确认运行时是否落后，但不把版本差当成必然根因
2. 任何"模式""标记"字段必须确认语义和归属表，不望文生义
3. wing.db 修改不触发自动 reload，涉及 DNS/routing 变更后手动 reload 验证
4. 文档补充：daed 的 DNS routing 规则存在 wing.db 存储但运行时可能未加载，reload 是标准检查手段
5. **公开仓库的尸检报告/文档必须用占位符替换真实 IP、域名、用户名**
