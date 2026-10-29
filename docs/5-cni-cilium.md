## Cilium CNI

### link

- [Run your Kubernetes Cluster on “Bare Metal” with Cilium CNI — Part. 1](https://itnext.io/run-your-kubernetes-cluster-on-bare-metal-with-cilium-cni-part-1-e88028800d90)
- [bare-metal-kubernetes-part-2-cilium-and-firewalls](https://datavirke.dk/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/)
- [bootstrapping-k3s-with-cilium](https://blog.stonegarden.dev/articles/2024/02/bootstrapping-k3s-with-cilium/)


### 实践

#### 安装

因为我们已经禁用flannel，那么我们需要在集群中安装cilium，才能启动flux。

> [link](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-cilium)

```bash
# 与 bootstrap/helmfile.yaml 一致（chart 与 values 路径都取自该处）；
# 版本以 Flux 中定义的 k8s/infra/common/kube-system/cilium/app/ocirepository.yaml 为准
helm install cilium oci://ghcr.io/home-operations/charts-mirror/cilium --version 1.18.6 --namespace kube-system -f k8s/infra/common/kube-system/cilium/app/values.yaml
helm upgrade cilium oci://ghcr.io/home-operations/charts-mirror/cilium --version 1.18.6 --namespace kube-system -f k8s/infra/common/kube-system/cilium/app/values.yaml

cilium status --wait

# 如果出现flux helmrrelease卡住(cilium升级)导致后面的kustomization无法执行
flux suspend hr cilium -n kube-system
flux resume hr cilium -n kube-system
#或者在 HelmReleases 中让这个无限尝试（当前 install.remediation.retries 已是 -1；upgrade 为 2）
# install:
#   remediation:
#     retries: -1
```

### ipam

ipam.mode 无法随意切换变更，如果要变更最好是建立新的集群
