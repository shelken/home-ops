# 运维笔记

本文件收纳常见排障入口。遵循 GitOps：常规变更走 Git + Flux；直接操作集群仅用于 bootstrap、只读排查或明确的事故恢复场景

## Flux

### OCIRepository API 版本不匹配

现象：

```text
dry-run failed: no matches for kind "OCIRepository" in version "source.toolkit.fluxcd.io/v1"
```

处理：检查本地 Flux CLI 版本。`OCIRepository` 在 Flux 2.6 起升级为 `v1`，Flux 2.5 为 `v1beta2`。本地 CLI 过旧时先升级 CLI，再让 bootstrap 与 Flux 自行管理集群内版本

### HelmRelease / Kustomization 卡住

优先排查近期提交是否引入不一致，不将 suspend / resume 作为常规同步手段。事故恢复时可执行：

```bash
flux suspend helmrelease cilium -n kube-system
flux resume helmrelease cilium -n kube-system
```

## Longhorn

### 卸载 Longhorn 前的确认标记

删除 Longhorn HelmRelease 前，需要显式设置删除确认标记：

```bash
kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
```

属于危险操作，仅在明确需要彻底销毁 Longhorn 时执行

### DaemonSet Misscheduled

k3s 或宿主机重启后，Longhorn DaemonSet 可能出现 Misscheduled。先排查节点、taint、调度约束与 Longhorn 状态；确认残留陈旧 Pod 后，删除对应 Pod 触发控制器重建

## Cilium

### 重建后 Gateway IP 不工作

重建集群后若 Cilium 未分配 Gateway IP，可通过 Task 任务重启 Cilium 组件：

```bash
task restart-cilium
```

### L2 宣告与 `externalTrafficPolicy=Local`

当服务需要 LoadBalancer IP 且 leader lease 漂移至未调度后端 Pod 的节点时，若配置了 `externalTrafficPolicy=Local`，入站流量会被丢弃

事故恢复时可删除对应 lease 触发重新选主（属于删除操作，执行前必须确认目标 lease）：

```bash
kubectl delete lease <LEASE_NAME> -n kube-system
```

长期防范方案：此类服务应至少配置两个副本，避免单节点调度与 L2 leader 错位

## Lima

### 磁盘无法挂载

现象：

```json
{
  "level": "fatal",
  "msg": "failed to run attach disk \"longhorn\", in use by instance \"sakamoto-k8s\""
}
```

处理：确认无活跃实例占用目标磁盘后执行解锁：

```bash
limactl disk unlock longhorn
```

## External Secrets

### Secret 迁移后 PushSecret 失败

External Secrets 会对受管外部密钥打 tag。迁移未保留 tag 会导致 PushSecret 校验失败。排查时确认目标 secret 归属，必要时清理远端错误数据后触发重试

## SMB

### 中文乱码

宿主机可能缺少 CIFS 相关组件：

```bash
sudo apt-get install -y cifs-utils linux-modules-extra-$(uname -r)
```

### SMB 相关容器规律性重启

若重启均集中于 SMB 挂载类服务，优先排查 `smb-scaler` 链路：

1. KEDA 消费 Prometheus 指标评估 SMB 服务状态
2. Blackbox 经由域名探测 SMB 端口连通性
3. 内网域名解析异常时 Blackbox 报错，进而干扰 scaler 伸缩决策

排查顺序：先确认 Blackbox 探测结果，再校验 DNS 解析链路，最后检查宿主机实际 SMB 会话

## Multus

### Pod 同时存在两个实例且网卡无法获取

配置 Multus 的工作负载不适用滚动更新（RollingUpdate），旧 Pod 尚未释放会导致新 Pod 无法分配 IP 与网卡；挂载 `ReadWriteOnce` PVC 的单实例应用同理

如果上游 chart 默认设置滚动更新，可以用 postRenderer 去除滚动更新策略：

```yaml
postRenderers:
  - kustomize:
      patches:
        - target:
            kind: Deployment
            name: xxx
          patch: |-
            - op: remove
              path: /spec/strategy/rollingUpdate
```
