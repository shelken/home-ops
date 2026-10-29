
## 挂载到特定机器

> 当前已不按节点限制：`nodeAffinityLabels`（原 `openebs.io/node-sakamoto`）与 basePath 一起被改掉（commit f1f83772“移除节点限制”），也没有对应的节点 label 命令。

```yaml
spec:
  values:
    localpv-provisioner:
      localpv:
        image:
          registry: quay.io/
        basePath: &hostPath /var/mnt/local-hostpath
      hostpathClass:
        enabled: true
        name: openebs-hostpath
        isDefaultClass: false
        basePath: *hostPath
```

节点名见 `ansible/inventory/hosts.ini`（`sakamoto-k8s` / `homelab-1` / `yuuko-k8s`），旧文档里的 `lima-sakamoto2` 已不存在。
