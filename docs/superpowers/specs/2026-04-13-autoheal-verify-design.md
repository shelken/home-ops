# Autoheal 验证命令设计

> **作用：** 定义 `task verify:autoheal` 的命令交互和命令输出，保证用户执行一条命令就能直观看到 `restart-passwall.sh` 与 `reconnect.sh` 在真实恢复链路中的效果。本文档只约束验证命令的交互、输出和结果判定。

## 目标

- 提供单命令入口 `task verify:autoheal`
- 使用 Charm 的 `gum` 提供人性化终端交互
- 终端直接展示两个自愈脚本的有效性证据
- 输出在屏幕内闭环，不依赖额外日志文件

## 范围

- 覆盖 `restart-passwall.sh` 的真实恢复验证
- 覆盖 `reconnect.sh` 的真实恢复验证
- 覆盖命令启动确认、阶段输出、最终结果展示

## 非目标

- 不定义实现细节之外的集群拓扑调整
- 不定义额外的 Web UI 或图形界面
- 不定义离线模拟或本地假服务验证

## 命令入口

固定入口：

```bash
task verify:autoheal
```

命令启动后先展示风险提示卡片，再通过 `gum confirm` 等待用户确认。

## 交互设计

### 启动确认

启动阶段使用 `gum style` 渲染风险提示，明确两次真实动作：

- 重启 passwall
- 触发 ZTE F50 断网重连

提示卡片要包含网络短暂抖动预期。确认交互使用 `gum confirm`，用户确认后才进入执行阶段。

### 执行阶段

执行过程按目标拆成两个连续区段：

1. `PASSWALL`
2. `F50`

每个区段都展示四个证据点：

1. 故障已出现
2. 告警已命中
3. 脚本已执行
4. 服务已恢复

等待阶段使用 `gum spin --title`，阶段完成后立刻输出人话结果。

## 输出设计

### 过程输出

过程输出采用事件流，直接说明当前发生了什么。目标格式如下：

```text
[PASSWALL] 故障已出现: router-dns-proxy 失败
[PASSWALL] 告警已命中: autoheal=passwall-restart
[PASSWALL] 脚本已执行: ok: passwall restart requested
[PASSWALL] 服务已恢复: router-dns-proxy 成功

[F50] 故障已出现: router-generate-204 失败
[F50] 告警已命中: autoheal=f50-network
[F50] 脚本已执行: ok: disconnect=... connect=...
[F50] 服务已恢复: router-generate-204 成功
```

过程输出要求：

- 每条消息都带目标前缀，固定为 `PASSWALL` 或 `F50`
- 每条消息都直接给出当前阶段结果
- 成功消息显示关键返回值或关键观测对象
- 失败时直接打印失败阶段和失败原因

### 结果输出

命令末尾使用 `gum style` 输出结果卡片，固定展示两个目标和整体结果：

```text
AUTOHEAL VERIFY
PASSWALL  PASS  49s
F50       PASS  71s
```

失败结果示例：

```text
AUTOHEAL VERIFY
PASSWALL  PASS  49s
F50       FAIL  timeout 180s
```

结果卡片要求：

- 显示 `PASSWALL` 与 `F50` 的独立状态
- 显示每个目标的耗时
- 显示整体结果 `PASS` 或 `FAIL`
- 不输出额外日志文件路径

## 成功判定

`PASSWALL` 成功条件：

- 终端显示代理 DNS 故障已出现
- 终端显示 `autoheal=passwall-restart` 已命中
- 终端显示 CGI 返回 `ok: passwall restart requested`
- 终端显示代理 DNS 已恢复

`F50` 成功条件：

- 终端显示外网故障已出现
- 终端显示 `autoheal=f50-network` 已命中
- 终端显示 CGI 返回 `ok: disconnect=... connect=...`
- 终端显示外网连通已恢复

整体成功条件：

- `PASSWALL` 与 `F50` 都为 `PASS`
- 命令退出码为 `0`

## 失败处理

任一目标在任一阶段失败时，命令继续输出该目标的失败信息并结束整个验证流程。失败输出必须包含：

- 失败目标
- 失败阶段
- 失败原因

失败时命令退出码为非 `0`。

## 依赖

- `task`
- `gum`
- 仓库当前自愈链路涉及的真实恢复资源

## 约束

- 只保留一条用户入口命令
- 屏幕输出本身要能完成审查
- 交互和输出使用中文
- 命令契约优先保证直观性，其次保证细节完整
