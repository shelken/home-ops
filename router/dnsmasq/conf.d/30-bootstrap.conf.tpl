# home-ops 集群外自举记录。
#
# 为什么用 address= 而不是 addn-hosts：address= 让 dnsmasq 对该名字全类型本地权威
# （A 答 192.168.6.144，AAAA 答 NODATA），任何类型都不再按 server=/int.ooooo.space/
# 转发给 k8s-gateway。addn-hosts 只登记 A 记录，AAAA 查询会穿透转发，把自举解析
# 静默耦合回集群可用性——2026-10-21 k8s-gateway 自身滚动重启期间，节点拉镜像的
# AAAA 查询超时报 Try again，k3s 退避 4.5 分钟叠加 Helm 5 分钟死线，kopiur 升级
# 连锁锁死在 UpgradeFailed。自举记录的存在意义就是集群挂了也要能解析，必须在
# 本层对全部记录类型闭合。
#
# 名字集合是 compose/sakamoto/configs/caddy/Caddyfile 里 internal-access 行的投影：
# 那边加一个站点，这里加一行。域名在本层是字面量（无 Flux 注入，同
# ansible/playbooks/resource/registries.yaml）。
#
# 代价：address= 不产生 PTR 反解（addn-hosts 有）；当前栈无反向解析消费方。
# 生效：随本目录下发到 /etc/dnsmasq-home-ops.d，由机器级接入点加载。
# 下发：task router:dns:diff 比对，task router:dns:sync 落地。

# local= 让该名字对所有记录类型本地闭合（含 AAAA 的 NODATA）；
# address= 只约束 A 查询，AAAA 在 dnsmasq 2.91 仍会按 server= 转发（已实测）。
local=/minio-ui.int.ooooo.space/
local=/minio.int.ooooo.space/
local=/nvidia-dls.int.ooooo.space/
local=/pve-mine.int.ooooo.space/
local=/ghcr-mirror.int.ooooo.space/
local=/quay-mirror.int.ooooo.space/
local=/mirror-gcr-mirror.int.ooooo.space/
local=/k8s-mirror.int.ooooo.space/

address=/minio-ui.int.ooooo.space/192.168.6.144
address=/minio.int.ooooo.space/192.168.6.144
address=/nvidia-dls.int.ooooo.space/192.168.6.144
address=/pve-mine.int.ooooo.space/192.168.6.144
address=/ghcr-mirror.int.ooooo.space/192.168.6.144
address=/quay-mirror.int.ooooo.space/192.168.6.144
address=/mirror-gcr-mirror.int.ooooo.space/192.168.6.144
address=/k8s-mirror.int.ooooo.space/192.168.6.144
