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
| `router/dnsmasq/conf.d/20-hosts.conf.tpl` | `20-hosts.conf` |
| `router/dnsmasq/dnsmasq-int.hosts` | `int.hosts` |

`20-hosts.conf` 从同一目录加载 `int.hosts`。集群服务记录不写入路由器；k8s-gateway 根据
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

集群不可用时，集群服务名称无法解析；`int.hosts` 中的集群外自举名称仍由路由器本地回答。
