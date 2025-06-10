## flux

> [教程 flux-git-ops](https://fschoenberger.dev/homelab/04-flux-git-ops/)

```shell

nix shell nixpkgs#fluxcd

```

创建staging cluster，分别创建infra和apps目录，按照官方的目录结构，apps中分为base和对应cluster名字。infra中分为controllers和configs。cluster则根据实际集群名。

在cluster例如staging，分别引用apps和infra的资源路径。

