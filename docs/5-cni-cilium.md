## Cilium CNI

### link

- [Run your Kubernetes Cluster on “Bare Metal” with Cilium CNI — Part. 1](https://itnext.io/run-your-kubernetes-cluster-on-bare-metal-with-cilium-cni-part-1-e88028800d90)
- [bare-metal-kubernetes-part-2-cilium-and-firewalls](https://datavirke.dk/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/)
- [bootstrapping-k3s-with-cilium](https://blog.stonegarden.dev/articles/2024/02/bootstrapping-k3s-with-cilium/)


### 实践

#### 安装

因为我们已经禁用flannel，那么我们需要在集群中安装cilium，才能启动flux。

> [link](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-cilium)

```shell
# 这里的版本根据flux中定义的来，如果不一致也没关系。flux后续会重新安装定义的版本。但是最好一直，省的二次下载安装
helm install cilium cilium/cilium --version 1.18.3 --namespace kube-system -f infra/common/kube-system/cilium/app/values.yaml
helm upgrade cilium cilium/cilium --version 1.18.3 --namespace kube-system -f infra/common/kube-system/cilium/app/values.yaml

cilium status --wait

# 如果出现flux helmrrelease卡住(cilium升级)导致后面的kustomization无法执行
flux suspend hr cilium -n kube-system
flux resume hr cilium -n kube-system
#或者在 HelmReleases 中让这个无限尝试。
# upgrade:
#   remediation:
#     retries: -1
```

### ipam

ipam.mode 无法随意切换变更，如果要变更最好是建立新的集群
