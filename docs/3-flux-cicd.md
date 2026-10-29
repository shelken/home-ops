# Flux GitOps

> 项目使用 `flux-operator` 与 `flux-instance` 声明式管理 Flux 组件，不再使用 CLI 的 `flux bootstrap` 初始化
> 参考文档：[Flux GitOps Guide](https://fschoenberger.dev/homelab/04-flux-git-ops/)
```bash
# 进入仓库根目录后 mise 自动提供 flux
```

集群采用分层目录架构：`k8s/apps` 与 `k8s/infra` 分别由 `common`（跨集群复用声明）与集群名目录（如 `staging`）组成，`k8s/clusters/<集群名>` 提供 Flux 入口 Kustomization

集群初始化统一执行 `task init`（自动完成 `task secret:bootstrap` 并通过 `helmfile -f bootstrap/helmfile.yaml sync` 部署 flux-operator 与 flux-instance）。以下 CLI `flux bootstrap` 仅保留作历史参考

```bash
# 在 GitHub 创建当前仓库使用的 token
export GITHUB_TOKEN="<GITHUB_TOKEN>"

flux bootstrap github \
--owner=shelken \
--repository=home-ops \
--branch=main \
--path=k8s/clusters/staging \
--personal \
--token-auth \

# 如果使用 SSH，可以带上 --private-key-file=<SSH_PRIVATE_KEY_PATH> 参数，去掉 token-auth
# --private 如果是私有仓库的话加上

# 将 sops-age / git-token-auth 等 bootstrap secret 放过去（见 bootstrap/resources.yaml）
task secret:bootstrap

```

## 代理与网络

- 官方参考：[Using HTTP/S proxy for egress traffic](https://fluxcd.io/flux/installation/configuration/proxy-setting/#using-https-proxy-for-egress-traffic)

使用 [`scripts/free-networks.sh`](../scripts/free-networks.sh) 脚本配置节点代理环境变量，加速 containerd 拉取镜像

强制 Flux 立即重新同步 Git 源：

```bash
flux reconcile source git flux-system
```
