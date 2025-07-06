
## 挂载到特定机器

```yaml
spec:  
  values:
    localpv-provisioner:
      localpv:
        image:
          registry: quay.io/
        basePath: &hostPath /mnt/data/openebs/local
      hostpathClass:
        enabled: true
        name: openebs-hostpath
        isDefaultClass: false
        basePath: *hostPath
        nodeAffinityLabels: 
          - "openebs.io/node-sakamoto"
```

```shell
# 固定openebs的卷到sakamoto
kubectl label node lima-sakamoto2 openebs.io/node-sakamoto=true
```