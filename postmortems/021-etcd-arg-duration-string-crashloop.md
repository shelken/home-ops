# etcd-arg duration 字符串导致 k3s crashloop

**日期**: 2026-09-25
**影响**: 控制面 k3s 重启失败进入 crashloop，单控制面集群 API 中断约 3 分钟（02:07-02:10）
**发现人**: 合并 PR #1478 后执行 ansible 验证时

## 问题

PR #1478 向 `k3s_server.etcd-arg` 添加 `experimental-warning-apply-duration=1s`（后修正为非弃用名 `warning-apply-duration`）。ansible 应用后 k3s 无法启动，反复 crashloop，控制面 API 完全不可用。

## 现象

```bash
ansible-playbook playbooks/install-k3s.yaml --limit controllers
# FAILED - RETRYING: xanmanning.k3s : Restart k3s systemd (x3)

sudo journalctl -u k3s -o cat | grep level=fatal
# level=fatal msg="Error: starting kubernetes: failed to start cluster: start managed
#   database: error unmarshaling JSON: while decoding JSON: json: cannot unmarshal
#   string into Go struct field configYAML.Config.warning-apply-duration of type
#   time.Duration"
```

## 根因

错误假设：**参数名正确 + ansible dry-run 通过 = 能生效**。

实际链路有两层类型转换，`1s` 在第二层断裂：

1. k3s `executor.ToConfigFile` 把 etcd-arg 合并进 etcd **YAML 配置文件**：`time.ParseDuration("1s")` 成功且键含 `duration` → 按 `time.Duration` 类型写入，**yaml.v2 对 time.Duration 特判序列化为字符串 `"1s"`**
2. etcd 侧 `configYAML` 经 sigs.k8s.io/yaml（YAML→JSON→json.Unmarshal）读取，`time.Duration`（int64）字段**只接受数字（纳秒）**，字符串直接 fatal

命令行 flag 形式 `--warning-apply-duration=1s` 本身合法；坏的只是 k3s 内嵌 etcd 走 YAML 配置文件这条路径。

缺失检查点：

- issue #1473 待办明确写了「**先验证** …… 在测试节点试，勿直接改仓库」，执行时跳过了
- PR 声称的效果（压制 99% 噪音）无实测，是复审时才发现 traceutil 阈值是硬编码常量
- dry-run（`--check`）只验证 ansible 声明层，永远不会触达「守护进程能否用新参数启动」

## 修复

1. 线上恢复：节点上手动把参数改为纳秒整数 `1000000000`，k3s 立即正常启动（02:10）
2. 仓库对齐：PR #1482（`warning-apply-duration=1000000000` + `warning-unary-request-duration=1000000000`），ansible `--check` 确认与集群零漂移
3. ansible 中保留注释说明纳秒约束，防止回归

## 预防

- k3s `etcd-arg` 传 duration/size 类参数一律用基础单位整数（纳秒/字节），不写 `1s`/`1Gi` 等带单位字符串
- 涉及守护进程启动参数的变更，合并前必须在等价环境实际启动验证；`--check --diff` 只能证明声明一致，不能证明可运行
- 控制面变更前先备好回滚命令（本次恢复用的是 `sed` + `systemctl restart`，若参数写错位置或 services 文件被改，恢复路径会完全不同）
- 单控制面集群的参数类变更，选择有观察窗的时段执行，合并后立即验证而非延后
