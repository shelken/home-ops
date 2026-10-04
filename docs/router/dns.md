# 路由器 DNS 配置

路由器 dnsmasq 的分流规则以文件声明在 `router/dnsmasq/conf.d/`，下发后等于路由器 `/etc/dnsmasq.d` 的内容。规则不再用 `uci set` / `add_list` 逐条修改。

## 职责

| 文件 | 内容 |
| :--- | :--- |
| `router/dnsmasq/conf.d/10-upstream.conf` | 主域与内部域都交集群里的 k8s-gateway；`strict-order` 之后按序回落公网 |
| `router/dnsmasq/conf.d/20-hosts.conf` | 引用集群外自举记录 `/etc/dnsmasq-hosts/int.hosts` |
| `router/dnsmasq/dnsmasq-int.hosts` | 集群外入口的精确记录（sakamoto 上的 minio、镜像代理等） |

集群内服务的记录不写在路由器：k8s-gateway 按当前集群资源应答，主域下集群内没有的名称由它转发公网递归。后端选择的理由见 [内网 DNS 后端](../adr/0003-internal-dns-via-gateway.md)。

## 一次性引导

dnsmasq 的 `confdir` 必须指向持久目录——默认的 `/tmp/dnsmasq.d` 在 tmpfs 上，重启即丢。

```bash
task router:dns:bootstrap
```

这一步同时清掉三处会让切换失败的旧状态，所以不要拆开手工做：

- `/etc/dnsmasq.d/int.hosts` 会被移出 confdir：`--conf-dir` **不带后缀过滤**，hosts 文件留在里面会被
  当作配置文件解析，dnsmasq 直接启动失败，整网断解析
- UCI 的旧 `addnhosts` 注册被删除：它与 `20-hosts.conf` 的 `addn-hosts` 指向同一批名字，
  重复注册会让同一个名字返回多个地址
- UCI 的 `allservers` 被删除：它让所有上游同时被问，与声明里的 `strict-order` 相冲，
  公网答案会和内网答案竞速（内网名可能在公网拿到 NXDOMAIN 而抢先返回）

这是唯一一次 UCI 变更；此后所有规则都由仓库文件声明。紧跟 `task router:dns:sync` 下发声明——
在它跑完之前，自举记录（`/etc/dnsmasq-hosts/int.hosts`）暂时不可解析。

## 下发

```bash
task router:dns:diff   # 只读：列出 conf 目录与 hosts 的差异，以及路由器上的多余文件
task router:dns:sync   # 下发 + 删除多余文件 + 重载 dnsmasq + 用路由器本机查询自举名验证
```

`sync` 先跑 `dns:diff`，确认之后才落地。

## 验证

```bash
dig @<ROUTER_IP> <CLUSTER_SERVICE_IN_MAIN_DOMAIN> A      # 期望：内网入口地址
dig @<ROUTER_IP> <PUBLIC_ONLY_NAME_IN_MAIN_DOMAIN> A     # 期望：公网答案
dig @<ROUTER_IP> <BOOTSTRAP_NAME> A                      # 期望：int.hosts 中的地址
ssh <ROUTER> 'cat /etc/dnsmasq.d/*.conf; cat /etc/dnsmasq-hosts/int.hosts'
```

- 集群不可用时，主域与内部域都靠 `strict-order` 的下一跳（公网）；故障期间首次查询要等上游超时
- gateway 的 `ttl` 为 60，dnsmasq 与客户端据此缓存；记录变更后最长 60 秒收敛
- 本地 hosts 与自举记录优先于转发规则，因此集群不可用时集群外入口仍可解析
