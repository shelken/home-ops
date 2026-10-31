# 路由器 DNS 配置

路由器 dnsmasq 同时承载 LuCI/UCI 手工配置与 home-ops 补充配置。基础配置保留在原有入口，
home-ops 持续同步只完整管理 `/etc/dnsmasq-home-ops.d`。

## 所有权

| 配置 | 所有者 |
| :--- | :--- |
| `/etc/config/dhcp` 中的全局选项与手工记录 | LuCI/UCI |
| `/etc/dnsmasq.conf` | 手工管理 |
| OpenWrt 自动生成的 `/tmp/dnsmasq.<instance>.d` | OpenWrt |
| `/etc/dnsmasq-home-ops.d` 中的全部内容 | home-ops |

`/etc/dnsmasq.conf` 必须包含专用目录接入点：

```text
# BEGIN home-ops dnsmasq
conf-dir=/etc/dnsmasq-home-ops.d,*.conf
# END home-ops dnsmasq
```

该接入点属于机器级配置，不由 `task router:dns:*` 维护。UCI `confdir` 保持未设置，因此
OpenWrt 的默认临时目录继续生效。

## 仓库声明

| 文件 | 专用目录中的目标 |
| :--- | :--- |
| `router/dnsmasq/conf.d/10-upstream.conf.tpl` | `10-upstream.conf` |
| `router/dnsmasq/conf.d/30-bootstrap.conf.tpl` | `30-bootstrap.conf` |

`conf.d/` 下的每个 `*.conf.tpl` 都会随下发渲染进专用目录（`router/dnsmasq/spec.py`）。`30-bootstrap.conf`
用 `address=` 与 `local=` 对集群外自举名称做本地权威应答，不依赖集群。集群服务记录不写入路由器；k8s-gateway 根据
当前 HTTPRoute、Service 和 Ingress 应答，主域下未匹配的名称由 gateway 转发公网递归。
后端选择见 [集群服务 DNS 决策](../adr/0003-internal-dns-via-gateway.md)。

## 下发

```bash
task router:dns:sync   # 默认入口：展示目录差异 → 确认 → 校验 → 下发 → 重启
task router:dns:diff   # 可选：只读展示专用目录差异
```

用户通常只需运行 `sync`；它会先自动执行同一份只读 diff。同步前使用临时目录校验完整配置，
同步时删除专用目录中仓库未声明的内容，其他 dnsmasq 配置保持原样。

## 验证

```bash
task router:dns:diff
ssh <ROUTER> 'grep -A2 -B1 "BEGIN home-ops dnsmasq" /etc/dnsmasq.conf'
ssh <ROUTER> 'ls -la /etc/dnsmasq-home-ops.d && cat /etc/dnsmasq-home-ops.d/*'
dig @<ROUTER_IP> <CLUSTER_SERVICE_IN_MAIN_DOMAIN> A
dig @<ROUTER_IP> <BOOTSTRAP_NAME> A
```

集群不可用时，集群服务名称无法解析；`30-bootstrap.conf` 中的集群外自举名称仍由路由器本地回答

判断解析失败原因前，先确认失败进程用的是哪个解析器：musl 报 `Try again` 或 `Name does not resolve`，glibc 报 `Temporary failure in name resolution`，Go 纯解析器不会输出这些文本。musl 的 `getaddrinfo` 对 A/AAAA 任一失败即判整名失败，报错文本本身就指向解析器类型

```bash
ssh <NODE> 'grep "trying next host" /var/lib/rancher/k3s/agent/containerd/containerd.log | tail -n 20'
```

k3s containerd 的逐端点失败与回退只写进 `containerd.log`，不进 journal，排查镜像拉取时不要只看 `journalctl`
