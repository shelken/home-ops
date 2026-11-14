---
date: 2026-11-13
status: accepted
---

# 路由器 BIRD 与 Avahi 的配置由 nix-config 声明

主路由 router-mine 的 `/etc/bird.conf`、`/etc/avahi/avahi-daemon.conf` 及对应软件包，由 nix-config 的 `hosts/router-mine/home-ops/` 用 nuci 声明并下发。home-ops 不再保存 BIRD 配置，也不再提供 `task router:bgp:*`。与 [ADR-0009](./0009-router-dnsmasq-declared-in-nix-config.md) 同一原则：同一台路由器的配置只有一个所有者

## Considered Options

- 继续由 home-ops 的 `declare.py` 下发 BIRD：路由器上 UCI 部分与 BIRD 分属两个仓库，换机时要两处重建
- 在 nix-config 里只存文件、手工校验与重载：下发后容易漏掉 `bird -p` 校验

## Consequences

- BIRD 的邻居地址取自 nix-config 的 `vars/networking.nix`，节点 IP 变化时改那里
- nuci 对 `uci.files` 只写文件，不校验也不重载。校验与重载放在 nix-config 的 `just router::push`：先 `bird -p`，通过才 `birdc configure`；avahi 配置有变化时才重启
- 失去 `declare.py` 的「先在暂存目录校验，再替换」：坏配置会先写到磁盘，`bird -p` 失败时 BIRD 继续运行旧配置，但磁盘上的文件需要手工修正
- 本仓库不再有 `router/` 目录，已断开站点的 BIRD 配置只留在 git 历史里
