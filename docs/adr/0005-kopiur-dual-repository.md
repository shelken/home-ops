# KOPIUR 双仓库：本地高频与云端每日直写

## 背景

集群 PVC 由 Kopiur 备份到宿主机 MinIO 的 `kopiur` 桶，每小时一次。宿主机 Kopia 再把 MinIO 目录整体快照到 OpenList（189 云盘）。两层叠加后，内层 Kopia 维护会把分散的小包合并成新 pack，外层无法识别这些 pack 的内容，只能按新文件重新上传。

实测：2026-10-18 03:02 内层 `full-rewrite-contents` 重写 6,751 条内容（655 MB），其中 31 个新 pack 合计 645.7 MB，占随后 06:30 云端快照增量的 88.29%。这类峰值由维护周期触发，与当天真实业务增量无关。

## 决策

1. `kopiur-system` 增加集群级仓库 `cloud-openlist`，直连集群内 OpenList S3 Service（`openlist.default.svc.cluster.local:5246`，明文 HTTP），与宿主机 Kopia 共用 `kopia` 桶但使用独立前缀 `kopiur/`。
2. 为解开冷启动依赖闭环（OpenList 应用依赖本地仓库就绪，若云端仓库阻塞等待 OpenList 则形成互相死锁），将云端仓库拆入独立的 `kopiur-repository-cloud` Flux Kustomization，设置 `wait: false`。
3. `components/kopiur/backup` 为每个应用同时生成两套独立策略与调度：
   - `${APP}`：本地 `sakamoto` 仓库，`H * * * *`，保留 24 小时 + 7 天 + 4 周
   - `${APP}-cloud`：`cloud-openlist` 仓库，`H 4 * * *`，只保留 7 天
4. 宿主机 Kopia 的 `@sakamoto` 忽略规则增加 `kopiur`，停止对本地仓库目录的二次快照。`cloudnative-pg` 等其他桶保持原样。
## 后果

- 云端每天只接收一份快照，不积累小时级碎片包，因此不会在云端触发小包合并后的周期性重传。每天上云量接近 24 小时净增量。
- 云端是独立的标准 Kopia 仓库，宿主机或本地 MinIO 全损时可直接从 OpenList 恢复，不必先还原整个 MinIO 再启动 Kopiur。
- 应用恢复默认仍指向本地策略；需要走云端时把恢复来源改为 `${APP}-cloud`。
- 两个仓库各自维护、各自保留，云端存储上限由 7 天保留策略约束。
- 宿主机 `kopiur` 桶的历史快照仍在云端，按既有保留期自然过期，不做手工删除。
- 云端仓库首次建立时，所有应用共用同一个仓库并跨应用共享内容去重。实测当前 12 个活跃应用的最新快照逻辑总量约 1.37 GiB（压缩后物理占用约 1~1.5 GB），这是唯一一次初始化全量上云，之后每天只传净增量。

## 验证记录

1. **OpenList S3 协议兼容性**：在隔离容器中通过 `kopia repository validate-provider` 验证，条件创建、部分/完整读取、元数据及并发测试全部通过。
2. **集群内 Service 通信**：从集群 Pod 内部直接请求 `http://openlist.default.svc.cluster.local:5246/kopia/`，确认为标准 S3 响应（403 InvalidAccessKeyId），无需经过外部 Envoy 路由与 TLS 终结。
3. **多客户端共享仓库去重**：实测两个独立配置连接同一仓库备份相同文件，数据块数量保持 1:1，跨源去重成立。
