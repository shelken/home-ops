# Kopia 经 openlist 写 WebDAV：MOVE 返回成功但改名未生效

**日期**: 2026-11-03
**症状关键词**: `unable to load manifest contents`、`BLOB not found`、`MOVE` 返回 201 后正式名不存在、存储里只剩带随机后缀的临时名、`database is locked`、仓库约 3 天没有新块
**影响**: 云端 Kopia 仓库索引引用了一个没有正式名的块，所有实例无法加载清单，快照写不进去，备份中断约 3 天

详细证据与复现见 #1763，前序问题见 #1722

## 症状

任一 Kopia 实例读仓库时报错：

```text
unable to load manifest contents: error getting cached content from blob "<块名>": BLOB not found
```

写入方都带重启策略，进入无限重启，每次重跑策略对账

## 根因

- 实际约束：Kopia 的 WebDAV 后端默认先 `PUT` 临时名，再 `MOVE` 成正式名。openlist 的 `MOVE` 偶发返回 201，但 139 云盘侧的改名没有生效，概率约 0.3% 到 0.7%
- 错误假设：以为 `MOVE` 返回成功就等于改名完成。Kopia 据此把块写进索引，之后整个仓库都依赖一个不存在的名字
- 缺失检查点：成功与失败的 openlist 日志完全一致，写入端和服务端都不会发现，只有读到那个块时才暴露

## 排查陷阱

- 怀疑 openlist 缓存：强制刷新目录缓存后云盘侧仍只有临时名，排除
- 怀疑 #1722 的补丁引入：补偿代码一次都没触发，也没测过未打补丁的版本，不能下结论
- 用 `MOVE` 的 HTTP 状态判断是否成功：不可靠，必须重新列目录核对正式名

## 修复

- 恢复缺失块：先备份目录列表与临时文件内容，确认正式名返回 404，再把临时文件内容直接 `PUT` 成正式名，不走 `MOVE`，读回核对大小
- 验证：`kopia snapshot list --all` 能列出全部来源，各写入方日志不再出现 `BLOB not found`
- 清理孤立临时文件：删除前逐个核对是否被索引引用，含已标记删除的内容

## 护栏

- 所有 Kopia 的 WebDAV 仓库配置必须带 `"atomicWrites": true`，让块直接 `PUT` 到最终名，绕开 `MOVE`。已落地于：
  - nix-config：`modules/features/backup/_kopia-server/entrypoint.sh`、`modules/features/backup/_kopia/secrets.nix`
  - 本仓库：`k8s/infra/common/kopiur-system/kopia/cloud/externalsecret.yaml`
- 新增或改动 Kopia WebDAV 仓库配置后，检查是否带该字段
  ```bash
  grep -rn atomicWrites k8s/infra/common/kopiur-system/
  ```
- 缺口：kopiur 的 `ClusterRepository/yun139` 同样写 openlist，但 `backend.webDav` 没有该字段，暂时无法对策。每次备份异常先看它的 `IndexBlobHealth` 与 `Ready` 状态，跟踪见 #1763
- 排查类似症状时，不信 `MOVE` 的状态码，直接在存储里确认该块目录下是正式名还是带随机后缀的临时名
