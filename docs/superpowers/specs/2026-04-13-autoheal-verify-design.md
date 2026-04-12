# Autoheal 本地验证设计

> **作用：** 定义 `task verify:autoheal` 与 `scripts/verify-autoheal.sh` 的本地交互流程、终端输出和测试边界，保证验证过程完全在本地执行，通过替身命令完成流程测试，同时保留 `restart-passwall.sh` 与 `reconnect.sh` 的黑盒脚本测试。

## 目标

- 提供单命令入口 `task verify:autoheal`
- 真实入口脚本放在 `scripts/verify-autoheal.sh`
- 终端交互使用 Charm 的 `gum`
- 包装脚本测试全程本地执行，只依赖替身命令
- 保留两个 CGI 脚本的黑盒测试

## 范围

- 包装脚本的本地交互和输出
- 包装脚本的成功流与失败流
- `restart-passwall.sh` 的黑盒测试
- `reconnect.sh` 的黑盒测试

## 非目标

- 不接入 Alertmanager
- 不接入 Flux
- 不创建 Job
- 不触发任何集群内执行体
- 不写额外日志文件

## 命令入口

固定入口：

```bash
task verify:autoheal
```

底层脚本：

```bash
./scripts/verify-autoheal.sh
```

## 架构

本次实现只分两层：

1. 本地包装脚本
   负责 `gum` 交互、步骤提示、触发命令、恢复检查和结果卡片。
2. 脚本测试
   - 包装脚本测试：替身 `gum`、`curl`、`sleep`
   - CGI 脚本测试：替身 `wget`、`mkdir`、`rmdir`、`sleep`、`date`

两层边界固定。包装脚本不读取集群状态，不依赖远端控制面，不生成声明式运行资源。

## 交互设计

### 启动卡片

脚本启动后先显示一张 `gum style` 卡片，内容只说明本次会验证：

- `PASSWALL`
- `F50`

随后使用 `gum confirm` 做一次确认。

### 过程输出

执行过程按两个目标顺序输出：

1. `PASSWALL`
2. `F50`

每个目标都输出固定的人话事件流：

```text
[PASSWALL] 开始验证
[PASSWALL] 触发脚本
[PASSWALL] 脚本执行成功
[PASSWALL] 检查恢复
[PASSWALL] 恢复结果正常
```

```text
[F50] 开始验证
[F50] 触发脚本
[F50] 脚本执行成功
[F50] 检查恢复
[F50] 恢复结果正常
```

等待动作使用 `gum spin`。事件流使用普通终端输出。

### 结果卡片

流程结束后使用 `gum style` 输出结果卡片：

```text
AUTOHEAL VERIFY
PASSWALL  PASS
F50       PASS
```

失败时直接显示失败目标：

```text
AUTOHEAL VERIFY
PASSWALL  PASS
F50       FAIL
```

## 本地数据流

### 包装脚本

包装脚本只做两类动作：

1. 触发动作
   调用本地可替身命令，拿到脚本执行结果文本。
2. 恢复检查
   调用本地可替身命令，轮询直到成功或超时。

触发地址和检查地址都通过环境变量注入，方便本地测试替换。

### CGI 脚本

CGI 脚本继续按现有方式单独测试，保持黑盒执行，不通过包装脚本间接覆盖。

## 成功判定

包装脚本成功条件：

- 用户确认后进入执行
- `PASSWALL` 输出成功事件流
- `F50` 输出成功事件流
- 结果卡片显示两者都是 `PASS`
- 退出码为 `0`

包装脚本失败条件：

- 用户取消，直接退出
- 任一目标触发失败
- 任一目标恢复检查超时
- 结果卡片显示失败目标
- 退出码为非 `0`

CGI 脚本成功判定保持现有测试约束：

- 请求方法过滤
- `autoheal` 标签过滤
- 环境变量校验
- 下游命令调用参数校验
- 锁行为校验

## 测试设计

### 包装脚本测试

新增测试文件：

```text
tests/scripts/test_verify_autoheal.py
```

覆盖 3 条主线：

1. 用户取消后退出
2. 成功流输出完整
3. 失败流停在对应目标并输出 `FAIL`

### CGI 脚本测试

保留现有两个测试文件：

```text
tests/k8s/infra/common/network/internal/passwall-healer/app/resources/test_restart_passwall.py
tests/k8s/apps/common/zte-mifi-exporter/app/resources/test_reconnect.py
```

必要时只补缺失分支，不改生产脚本逻辑。

## 文件边界

- `scripts/verify-autoheal.sh`
  作用：本地包装脚本，负责交互和输出。
- `tests/scripts/test_verify_autoheal.py`
  作用：本地包装脚本测试。
- `tests/k8s/infra/common/network/internal/passwall-healer/app/resources/test_restart_passwall.py`
  作用：`restart-passwall.sh` 黑盒测试。
- `tests/k8s/apps/common/zte-mifi-exporter/app/resources/test_reconnect.py`
  作用：`reconnect.sh` 黑盒测试。
- `Taskfile.yaml`
  作用：提供 `verify:autoheal` 入口。

## 约束

- 全程本地流程
- 所有交互和输出使用中文
- 包装脚本只做 orchestration
- 测试只用替身命令控制外部依赖
- 不增加集群侧资源
