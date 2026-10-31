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

长期卡在 `Ready: False` 时先查 HelmRelease 是否 `Stalled: True`

```bash
flux get hr -A
```

`Stalled` 是终态（`Reason: RetriesExceeded`，默认 `install.remediation.retries: 0`），控制器不再自动重试，`kustomize-controller` 的 healthCheck 会因 `stalled resources` 直接短路，把 `infra` → `apps` 整链拖死；此时底层 Pod 往往本身健康。解除方式是删除该 HelmRelease 触发重新对账

### 子级停滞定位

按父级到子级的顺序看：`flux get ks -A` 找 blocked 的父级，kustomize-controller 日志看失败原因，再看失败子级的 `next try in`。未声明 `retryInterval` 的子级按 `interval` 重试，几秒的竞态会被放大成小时级等待

### postBuild 变量消费方

新增 postBuild 变量时必须核对三种替换机制，漏一处即在 strict 模式下失败：

- Flux `substituteFrom`（子 Kustomization 的 postBuild）
- 进程内展开：标注 `substitution.flux/disabled: "true"` 的资源不会被 Flux 替换，需自行补 Deployment env 等
- kustomize 层替换

## Longhorn

### 卸载 Longhorn 前的确认标记

删除 Longhorn HelmRelease 前，需要显式设置删除确认标记：

```bash
kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag
```

属于危险操作，仅在明确需要彻底销毁 Longhorn 时执行

### DaemonSet Misscheduled

k3s 或宿主机重启后，Longhorn DaemonSet 可能出现 Misscheduled。先排查节点、taint、调度约束与 Longhorn 状态；确认残留陈旧 Pod 后，删除对应 Pod 触发控制器重建

### DiskFilesystemChanged 后重新纳入磁盘

出现 `reason: DiskFilesystemChanged` 时 Longhorn 不会自动接纳：Node spec 与 status 仍记录旧 UUID，磁盘上的 `longhorn-disk.cfg` 已是新 UUID，磁盘停在 `Ready=False`、`Schedulable=False`，即使文件系统可挂载也不会恢复调度

动 disk entry 之前先处理仍停在盘上的临时恢复卷与 replica CR：暂停对应子 Kustomization，确认这些卷无业务 Pod 挂载、源端快照可用后，删除对应应用的 Kustomization（PVC 与 `Restore` 随 prune 级联重建），让 Longhorn 卷与 replica CR 一并清理，不强删 finalizer（恢复流程见 `skill://kopiur-restore`）

重新纳入磁盘：

```bash
# 1. 确认挂载路径是预期挂载点、容量正确，且不是系统盘目录
kubectl -n longhorn-system get nodes.longhorn.io <NODE> -o jsonpath='{.spec.disks}'
# 2. 从 spec.disks 删除旧 disk entry，等待对应 status.diskStatus 消失
# 3. 用相同 diskName、相同挂载路径和原 storageReserved 重新添加，并设置 allowScheduling: true
kubectl -n longhorn-system get nodes.longhorn.io <NODE> -o jsonpath='{.status.diskStatus}'
# 4. 校验磁盘读取到新 UUID，且 Ready=True、Schedulable=True、可用容量正常
```

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

### subPath 目录创建失败

容器创建时报：

```text
Error: failed to create subPath directory for volumeMount "backup-media" of container "app"
```

处理：在 SMB 服务所在主机上重启 `smbd`

```bash
sudo launchctl stop com.apple.smbd && sudo launchctl start com.apple.smbd
```

`smb_mount_healthy` 只探测挂载点是否可读，探不到这个症状，需从容器事件反查

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

## 网络层

### TCP 连上但 TLS 握手超时

先画清到目标的下一跳是 eth0 还是 Tailscale 接口，再逐口对照 MTU，最后才排 DNS 与服务端。TLS 握手中的 ServerHello/Certificate 远大于三次握手与 ClientHello，MTU 黑洞的典型表现就是 TCP connect 成功、TLS handshake timeout，多个不相关目标（镜像仓库、网盘 API、对象存储）同时异常时优先怀疑公共网络层，不要逐个应用修补

抓包读到的 SYN mss 只是当时按哪份 MTU 切段的读数，改动应落回各口与路径的 MTU 声明

- 供应商迁移、换机房、换上游、启用 DDoS 清洗后，把各口与路径 MTU 是否统一列为第一批检查项
- 公网腿用 `interface_mtu` 声明统一，Docker 容器腿用 compose `driver.mtu` 与 Tailscale 的 1280 对齐
- 改 Docker 网络 MTU 必须重建 network，`compose up` 不会更新已有 bridge 的 mtu

### 改完配置先确认运行进程是否已重载

- daed 的 wing.db 改动不触发自动 reload，DNS/routing 变更后须手动 reload 再验证
- 被运行进程按路径反复读取的文件（如 Envoy 的 mmdb）必须写临时文件后原子 `mv` 替换，就地覆盖会在热重载窗口内产生异常状态
- Docker Compose 只在服务定义变化时重建容器，只改 `configs:` 引用的文件不会重新加载，属同类问题（见 `compose/AGENTS.md`）
