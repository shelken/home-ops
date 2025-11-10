## sidecar

给pod添加注解以启用sidecar，operator会自动变更容器。

helmrelease.yaml

```yaml
annotations:
  netbird.io/setup-key: ${APP}-side-car-setup-key
```

需要同命名空间有这个 setup-key

ks.yaml

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &appname example
  namespace: &namespace default
spec:
  components:
    - ../../../../components/netbird/side-car
  postBuild:
    substitute:
      APP: *app
```
