# home-ops 领域术语

本文件定义 home-ops 中使用的领域术语

## Language

### 网络

**旁路由（Bypass router）**:
运行透明代理的那台 TVBox，是 K8s 节点与客户端的 IPv4 默认网关和 DNS 分流入口
_Avoid_: daed、dae（这两个是运行在旁路由上的程序，不是机器）

**源站（Upstream registry）**:
镜像原本所在的公开镜像仓库，例如 docker.io、ghcr.io、quay.io
_Avoid_: 上游镜像源、官方源

**镜像端点（Mirror endpoint）**:
为某个源站提供镜像拉取的替代地址，按顺序尝试，全部失败才回退到源站
_Avoid_: 镜像源、加速器、mirror
