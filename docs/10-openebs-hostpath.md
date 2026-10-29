# OpenEBS HostPath 本地存储

参考配置：[`k8s/infra/common/openebs-system/openebs/app/helmrelease.yaml`](../k8s/infra/common/openebs-system/openebs/app/helmrelease.yaml)

当前 OpenEBS HostPath 已移除特定节点亲和性限制（本仓库不再设置 `nodeAffinityLabels`），基准存储路径统一为 `/var/mnt/local-hostpath`：

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

集群实际节点名称以 `ansible/inventory/hosts.ini` 为准（`sakamoto-k8s`、`homelab-1`、`yuuko-k8s`）
