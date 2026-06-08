# 运维笔记

本文件收纳从 README 拆出的常见排障入口。默认遵循 GitOps：常规变更走 Git + Flux；直接操作集群只用于 bootstrap、只读排查或明确的事故恢复场景。

## Flux

### OCIRepository API 版本不匹配

现象：

```text
dry-run failed: no matches for kind "OCIRepository" in version "source.toolkit.fluxcd.io/v1"
```

处理：检查本地 Flux CLI 版本。`OCIRepository` 在 Flux 2.6 才是 `v1`，Flux 2.5 中是 `v1beta2`。本地 CLI 过旧时，先升级 CLI，再让 bootstrap / Flux 自身管理集群内版本。

### HelmRelease / Kustomization 卡住

优先确认是否是近期提交导致的 GitOps 状态不一致。不要把 suspend/resume 当作常规同步方式。

事故恢复时可考虑：

```shell
flux suspend helmrelease cilium -n kube-system
flux resume helmrelease cilium -n kube-system
```

## Longhorn

### 卸载 Longhorn 前的确认标记

删除 Longhorn HelmRelease 前，需要显式设置删除确认标记：

```shell
kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
```

这是危险操作，只能在确认要删除 Longhorn 时执行。

### DaemonSet Misscheduled

k3s 或宿主机重启后，Longhorn DaemonSet 可能出现 Misscheduled。先检查节点、taint、调度约束和 Longhorn 状态；确认是陈旧 Pod 后，再删除对应 Pod 让控制器重建。

## Cilium

### 重建后 Gateway IP 不工作

重建集群后，如果 Cilium 没有正确分配 Gateway IP，可用项目任务重启 Cilium 相关组件：

```shell
task restart-cilium
```

### L2 宣告与 `externalTrafficPolicy=Local`

当服务需要 LoadBalancer IP，且 leader lease 落在没有后端 Pod 的节点上时，如果服务设置了 `externalTrafficPolicy=Local`，流量可能被丢弃。

事故恢复时可以删除对应 lease 让控制器重新选主；这是删除操作，执行前必须确认目标 lease：

```shell
kubectl delete lease <LEASE_NAME> -n kube-system
```

长期修复方向：这类服务应至少运行两个副本，避免单节点调度与 L2 leader 不匹配。

## Lima

### 磁盘无法挂载

现象：

```json
{
  "level": "fatal",
  "msg": "failed to run attach disk \"longhorn\", in use by instance \"sakamoto-k8s\""
}
```

处理：确认没有实例正在使用该磁盘后解锁。

```shell
limactl disk unlock longhorn
```

## External Secrets

### Secret 迁移后 PushSecret 失败

External Secrets 会给由它管理的外部 secret 打 tag。迁移时如果没有带上这些 tag，PushSecret 可能失败。

处理方向：确认目标 secret 是否应由 External Secrets 管理；如果是，删除外部侧错误迁移的 secret，让 External Secrets 重新同步。

## SMB

### 中文乱码

宿主机可能缺少 CIFS 相关组件：

```shell
sudo apt-get install -y cifs-utils linux-modules-extra-$(uname -r)
```

### SMB 相关容器规律性重启

如果重启的都是 SMB 相关服务，优先检查 `smb-scaler` 链路：

1. KEDA 通过 Prometheus 指标判断 SMB 服务状态。
2. Blackbox 使用域名探测 SMB 端口连通性。
3. DNS 无法解析 LAN 域名时，Blackbox 会失败，进而影响 scaler 判断。

排查顺序：先看 Blackbox 探测结果，再看 DNS 解析，再看当前 SMB 连接情况。

## Multus

### Pod 同时存在两个实例且网卡无法获取

设置了 Multus 的工作负载不适合滚动更新，因为旧 Pod 可能仍占用网卡。带 `ReadWriteOnce` PVC 的工作负载也经常不适合滚动更新。

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
