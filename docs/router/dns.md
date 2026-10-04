# 路由器 DNS 配置

路由器 dnsmasq 同时承载 LuCI/UCI 手工配置与 home-ops 补充配置。两者按所有权分开：
手工配置保留在现有入口，home-ops 独占额外增加的 conf-dir 和自举 hosts 文件。

## 所有权

| 配置 | 所有者 |
| :--- | :--- |
| `/etc/config/dhcp` 中的全局选项、手工记录和其他 `addnhosts` | LuCI/UCI |
| `/etc/dnsmasq.conf` 中 home-ops 标记块之外的内容 | 手工管理 |
| `/etc/dnsmasq.conf` 中的 home-ops 标记块 | home-ops |
| OpenWrt 自动生成的 `/tmp/dnsmasq.<instance>.d` | OpenWrt |
| `/etc/dnsmasq-home-ops.d` | home-ops |
| `/etc/dnsmasq.d/int.hosts` 及其精确 `addnhosts` 条目 | home-ops |

home-ops 标记块向 dnsmasq 增加第二个 conf-dir：

```text
# BEGIN home-ops dnsmasq
conf-dir=/etc/dnsmasq-home-ops.d,*.conf
# END home-ops dnsmasq
```

UCI `confdir` 保持未设置，因此 OpenWrt 的默认临时目录继续生效。专用目录只加载 `.conf`
文件，`/etc/dnsmasq.d/int.hosts` 继续按 hosts 格式读取。

## 仓库声明

| 文件 | 内容 |
| :--- | :--- |
| `router/dnsmasq/conf.d/10-upstream.conf.tpl` | 将主域与内部域交给 k8s-gateway |
| `router/dnsmasq/dnsmasq-int.hosts` | 集群外入口的精确记录 |
| `router/dnsmasq/declare.py` | 对比、校验并同步 home-ops 所有的配置 |

集群服务记录不写入路由器。k8s-gateway 根据当前 HTTPRoute、Service 和 Ingress 应答，
主域下未匹配的名称由 gateway 转发公网递归。后端选择见
[集群服务 DNS 决策](../adr/0003-internal-dns-via-gateway.md)。

## 下发

```bash
task router:dns:sync   # 默认入口：展示差异 → 确认 → 校验 → 下发 → 重启
task router:dns:diff   # 可选：只读展示 home-ops 所有权范围内的差异
```

用户通常只需运行 `sync`；它会先自动执行同一份只读 diff。首次同步会添加 home-ops
标记块并创建专用目录，不需要独立 bootstrap。同步只删除专用目录中仓库未声明的
`.conf`，其他 dnsmasq 配置保持原样。

## 验证

```bash
task router:dns:diff
ssh <ROUTER> 'cat /etc/dnsmasq.conf'
ssh <ROUTER> 'cat /etc/dnsmasq-home-ops.d/*.conf'
ssh <ROUTER> 'uci -q get dhcp.@dnsmasq[0].addnhosts'
ssh <ROUTER> 'cat /etc/dnsmasq.d/int.hosts'
dig @<ROUTER_IP> <CLUSTER_SERVICE_IN_MAIN_DOMAIN> A
dig @<ROUTER_IP> <BOOTSTRAP_NAME> A
```

集群不可用时，集群服务名称无法解析；`int.hosts` 中的集群外自举名称仍由路由器本地回答。
