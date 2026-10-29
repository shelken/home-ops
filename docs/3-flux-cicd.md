# Flux GitOps

> NOTE: 目前项目不再使用CLI命令即`flux bootstrap`来初始化。而是使用`flux-instance`和`flux-operator`。
> [教程 flux-git-ops](https://fschoenberger.dev/homelab/04-flux-git-ops/)

```bash
# 进入仓库根目录后 mise 自动提供 flux
```

创建staging cluster。按官方目录结构：`k8s/apps` 与 `k8s/infra` 各分 `common`（所有集群共用）和集群名目录（`staging`），`k8s/clusters/<集群名>` 放该集群的 Kustomization 入口。

在cluster例如staging，分别引用apps和infra的资源路径。

初始化改走 `task init`（`task secret:bootstrap` + `helmfile -f bootstrap/helmfile.yaml sync`，装 flux-operator 与 flux-instance）。以下 `flux bootstrap` 为存档步骤，可能过时。

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

## 关于代理网络

- [Using HTTP/S proxy for egress traffic](https://fluxcd.io/flux/installation/configuration/proxy-setting/#using-https-proxy-for-egress-traffic)

使用[free-network](../scripts/free-networks.sh)脚本来让集群节点走代理，方便让containerd拉取镜像

可以使用以下命令强制 Flux 立刻尝试重新同步（reconcile）这个 Git 源，而不是等待它的定时周期。
`flux reconcile source git flux-system`

### 为flux的控制器加上代理

> 参考 [code](https://github.com/shelken/home-ops/commit/2af8e80051bf0ad8f265bc2667ea9ab8464cfa91)
>
