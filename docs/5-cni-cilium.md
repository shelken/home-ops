# Cilium CNI 部署与运维

## 参考链接

- [Run your Kubernetes Cluster on “Bare Metal” with Cilium CNI — Part. 1](https://itnext.io/run-your-kubernetes-cluster-on-bare-metal-with-cilium-cni-part-1-e88028800d90)
- [bare-metal-kubernetes-part-2-cilium-and-firewalls](https://datavirke.dk/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/)
- [bootstrapping-k3s-with-cilium](https://blog.stonegarden.dev/articles/2024/02/bootstrapping-k3s-with-cilium/)
- [Cilium 官方安装指南](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-cilium)

## 安装与引导

因 k3s 禁用了内置 Flannel 与 kube-proxy，集群引导初期需先安装 Cilium 为 Pod 提供网络，随后交付 Flux 接管：

```bash
# 引导期只安装 Cilium：版本、chart 来源与 values 均统一取自 bootstrap/helmfile.yaml
helmfile -f bootstrap/helmfile.yaml -l name=cilium sync

cilium status --wait

# 若出现 Flux HelmRelease 卡住（Cilium 升级）导致后续 Kustomization 无法执行
flux suspend hr cilium -n kube-system
flux resume hr cilium -n kube-system
# 若仍反复卡住，可在 HelmRelease 中将 upgrade.remediation.retries 调整为 -1（当前为 2，install 已配置为 -1）
```

## IPAM 模式

Cilium 的 `ipam.mode` 在集群初始化后无法直接就地切换，若需变更应在新建集群时规划
