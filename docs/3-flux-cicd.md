## flux

> NOTE: 目前项目不再使用CLI命令即`flux bootstrap`来初始化。而是使用`flux-instance`和`flux-operator`。
> [教程 flux-git-ops](https://fschoenberger.dev/homelab/04-flux-git-ops/)

```shell

nix shell nixpkgs#fluxcd

```

创建staging cluster，分别创建infra和apps目录，按照官方的目录结构，apps中分为base和对应cluster名字。infra中分为controllers和configs。cluster则根据实际集群名。

在cluster例如staging，分别引用apps和infra的资源路径。

然后使用flux bootstrap，引用对应repo。

```shell
# 在github创建具体仓库使用的githu token
export GITHUB_TOKEN=xxxx

flux bootstrap github \
--owner=shelken \
--repository=home-ops \
--branch=main \
--path=k8s/clusters/staging \
--personal \
--token-auth \ 

# 如果使用ssh，可以带上--private-key-file=~/.ssh/id_ed25519参数，去掉token-auth
# --private 如果是私有仓库的话加上

# 将sops-secret放过去
task deploy-secret

```

## 关于代理网络

- [Using HTTP/S proxy for egress traffic](https://fluxcd.io/flux/installation/configuration/proxy-setting/#using-https-proxy-for-egress-traffic)

使用[free-network](../scripts/free-networks.sh)脚本来让集群节点走代理，方便让containerd拉取镜像

可以使用以下命令强制 Flux 立刻尝试重新同步（reconcile）这个 Git 源，而不是等待它的定时周期。
`flux reconcile source git flux-system`

### 为flux的控制器加上代理

> 参考 [code](https://github.com/shelken/home-ops/commit/2af8e80051bf0ad8f265bc2667ea9ab8464cfa91)
> 
