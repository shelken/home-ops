# home-ops 领域词汇

home-ops 用 GitOps 管理 k3s 集群与集群外服务,本文件定义跨文档使用的领域术语

## Language

**外部服务**:
运行在 k3s 集群外、经 selector-less Service + EndpointSlice 注册进集群 DNS 的服务
_Avoid_: 集群外应用, 第三方服务

**宿主机**:
承载集群外服务负载的 Mac 物理机(ansible others.ini `[endpoint]` 组,如 yuuko、sakamoto);它与 k8s 节点(Lima VM)同机配对但不是同一台机器
_Avoid_: 主机(泛指), endpoint(仅作 inventory 分组名)

**服务注册**:
把一个外部服务声明为集群内 Service 的动作,产物为 Service + EndpointSlice,按需再加 HTTPRoute 与 gatus 探活
_Avoid_: 暴露, 接入
