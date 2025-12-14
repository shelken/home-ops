# 添加远程node或者轻量node

## tvbox

我们加上label node-type: lightweight

加上taint node-type=lightweight:NoSchedule

## 远程节点 yuuko-k8s

我们加上 label node-type: remote

加上taint node-type=remote:NoSchedule

## 服务指定

参考 echo

```
defaultPodOptions:
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "lightweight"
      effect: "NoSchedule"
  nodeSelector:
    node-type: lightweight
```

## 说明

重型的基础设施，不应该放到lightweight的节点上，例如longhorn

远程的节点也不适合各种数据传输，目前本地使用流量，与家里进行数据传输不现实，适合无状态容器和少数据传输的情况。

因此，添加服务时考虑这两点。
