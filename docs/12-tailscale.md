## 使用tailscale连接VPS和家庭网

> 目前限制：目前集群单栈ipv4 无法direct（通过ipv6）

- [文档](https://github.com/tailscale/tailscale/tree/main/docs/k8s)
- [文档](https://tailscale.com/kb/1282/docker)
- [kubernetes-operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [expose by annotating a service](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress#exposing-a-cluster-workload-by-annotating-an-existing-service)

1. 安装 kubernetes-operator
2. 配置好 oauth-client 和 tagOwner
3. 添加注解暴露gateway或者ingress

operator 的作用相当于在集群内监控资源，然后根据需要添加pod，在tailscale上创建指向具体服务的一个节点。

NOTE: 以下内容为docker相关变量，不需要，operator把下面这些事直接处理了。


```shell

SERVICE_CIDR=10.43.0.0/16
POD_CIDR=10.42.0.0/16
# 子路由 tailscale set --advertise-routes= 
export TS_ROUTES=$SERVICE_CIDR,$POD_CIDR

#在 Kubernetes 上运行时，状态默认存储在 name:tailscale 的 Kubernetes secret 中。如需将状态存储在本地磁盘上
TS_KUBE_SECRET=""
TS_STATE_DIR=/path/to/storage/dir

# 预认证密钥
TS_AUTHKEY=

# 在 tailscale up 命令中传递给 Tailscale CLI 的任何其他标志。
# --login-server=https://headscale.ooooo.space
# --advertise-tags=tag:k8s
TS_EXTRA_ARGS="--login-server=https://headscale.ooooo.space" --advertise-tags=tag:k8s

```
