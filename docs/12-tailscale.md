## 使用tailscale连接VPS和家庭网

> 目前限制：目前集群单栈ipv4 无法direct（通过ipv6）
> 
> 可尝试使用proxyclass来定义创建的资源，为class加上multus

- [文档](https://github.com/tailscale/tailscale/tree/main/docs/k8s)
- [文档](https://tailscale.com/kb/1282/docker)
- [kubernetes-operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [expose by annotating a service](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress#exposing-a-cluster-workload-by-annotating-an-existing-service)

1. 安装 kubernetes-operator
2. 配置好 oauth-client 和 tagOwner
3. 添加注解暴露gateway或者ingress

operator 的作用相当于在集群内监控资源，然后根据需要添加pod，在tailscale上创建指向具体服务的一个节点。
