# VPS MSS blackhole after migration

**日期**: 2026-07-08
**影响**: VPS 迁移后，Docker/Quay/ECR/OpenList 等多个 HTTPS 目标出现 TLS handshake timeout，导致镜像拉取失败、OpenList 后端存储不可读、Kopia 备份仓库打开失败；排查初期误判为 DNS、IPv6、Docker Hub/Quay 单站故障和容器 DNS 问题。
**发现人**: 用户

## 问题

VPS 供应商将 Budget VPS 物理迁移到新机房后，VPS 公网 IPv4 保持不变，但底层出口路径发生变化。迁移后，多个站点 TCP 443 可以建立连接，但 TLS 握手卡死。

故障影响的典型路径：

- `docker pull` 访问 Docker Hub/Quay 失败。
- OpenList 访问上游网盘 API 失败，S3 兼容层看不到后端对象。
- Kopia 通过 OpenList S3 打开仓库失败，报 `kopia.repository` blob 不存在。

## 现象

最小复现命令：

```bash
ssh <VPS_HOST> '
  curl -4 --connect-timeout 5 --max-time 15 -v https://registry-1.docker.io/v2/
  curl -4 --connect-timeout 5 --max-time 15 -v https://quay.io/v2/
  curl -4 --connect-timeout 5 --max-time 15 -v https://open.e.189.cn/
'
```

关键报错：

```txt
net/http: TLS handshake timeout
curl: SSL connection timeout
```

对照现象：

```txt
TCP connect 成功
TLS ClientHello 发出
ServerHello / Certificate 大段回包缺失
TLS handshake timeout
```

手动降低 TCP MSS 后全部恢复：

```txt
MSS 1460 -> Docker Hub / Quay / ECR / OpenList TLS timeout
MSS 1436 -> Docker Hub / Quay / ECR / OpenList TLS OK
```

抓包和阈值证据：

```txt
1436 MSS + 20 IPv4 header + 20 TCP header = 1476 MTU
1500 MTU - 1476 MTU = 24 bytes
```

`24 bytes` 与 GRE 等封装的典型额外开销吻合。VPS 迁移邮件中明确提到物理迁移、新机房和上游 provider transition，因此 IP 不变但底层路径变化是合理约束。

## 根因

错误假设：

- 以为 Docker Hub 单站故障，优先查 Docker 状态页。
- 以为 DNS 返回 IPv6 优先导致失败，先尝试过滤 AAAA。
- 以为改到 Quay 可以绕过 Docker Hub，忽略 Quay 也可能走同类大 MSS 路径。
- 以为 Kopia 的 `lookup openlist on 127.0.0.1:53` 是根因，忽略 `host` 网络容器和 bridge 网络容器的 DNS 语义差异。
- 以为 OpenList S3 返回 `BLOB not found` 是 Kopia 仓库损坏，差点把存储层错误当成数据层错误。

实际约束：

- IP 地址不变不代表路径不变；供应商可在新机房继续通过 BGP 广播原 IPv4 段。
- 机房迁移后，底层可能新增或切换 GRE/IPIP/VXLAN、DDoS 清洗、SDN 网关、边界路由器或上游回程。
- 新路径真实 PMTU 约为 1476，但 VPS `eth0` 仍看到 MTU 1500，默认 TCP MSS 仍是 1460。
- 路径上没有正确传递 PMTUD 所需 ICMP Fragmentation Needed，或没有在低 MTU 边界做 TCP MSS clamp，形成 PMTU/MSS 黑洞。
- TLS 握手里的 ServerHello/Certificate 比 TCP 三次握手和 ClientHello 更大，因此表现为“TCP 443 连上但 TLS timeout”。

缺失检查点：

- 没有第一时间做 MSS 阈值测试：默认 MSS、`TCP_MAXSEG=1436` 对照。
- 没有第一时间抓包确认 ServerHello 大段是否缺失。
- 没有把“迁移邮件/非正常停机时间线”和网络路径变化关联起来。
- 没有先区分应用层错误、DNS 错误、TLS 大包丢失和存储后端不可读。

## 修复

临时恢复方式：

```bash
iptables -t mangle -I POSTROUTING 1 \
  -o eth0 \
  -p tcp --tcp-flags SYN,RST SYN \
  -j TCPMSS --set-mss 1436
```

验证结果：

```txt
registry-1.docker.io  OK
quay.io               OK
public.ecr.aws        OK
open.e.189.cn         OK
Docker pull           OK
OpenList storage      work
Kopia repository      OK
```

持久化方式：

- 使用项目已有 Ansible + UFW，而不是新增 nftables 或手写裸 iptables。
- 在 `host_vars` 中声明 `ufw_tcp_mss_clamp`。
- 由 `ufw-vps.yml` 管理 `/etc/ufw/before.rules` 的 `*mangle` block。
- 同步 VPS 当前 UFW 端口规则，并让 playbook 删除未声明的简单 allow 规则。

项目侧关键配置：

```yaml
ufw_tcp_mss_clamp:
  enabled: true
  interface: eth0
  mss: 1436
```

UFW 持久化规则：

```txt
*mangle
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o eth0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1436
COMMIT
```

## 预防

- VPS 供应商迁移、换机房、换上游、启用 DDoS 清洗后，必须把 PMTU/MSS 作为第一批检查项。
- 遇到“TCP connect 成功但 TLS handshake timeout”，不要先假设 DNS 或服务端故障；先做 MSS 对照测试。
- 排查顺序固定为：DNS 解析 → TCP connect → TLS 抓包 → MSS 阈值 → 路径/迁移时间线 → 应用层。
- 对 Docker/Quay/ECR/OpenList 同时异常的情况，优先怀疑公共网络层，不要逐个应用修补。
- Kopia 报 `BLOB not found` 时，先验证后端对象层是否可读，不要直接判断仓库损坏。
- `host` 网络容器里 `127.0.0.1` 指宿主机；bridge 网络容器里 `127.0.0.1` 指容器自己。容器 DNS 排障必须先看 network mode。
- UFW 规则必须由 Ansible 收敛；临时 `iptables` 验证成功后，要尽快写回声明式配置。
- 给供应商工单时附带可复现证据：默认 MSS 1460 失败、MSS 1436 成功、抓包显示大 TLS 回包缺失。

参考：

- RFC 2923: TCP Problems with Path MTU Discovery: https://www.rfc-editor.org/rfc/rfc2923.html
- iptables TCPMSS target: https://manpages.debian.org/bookworm/iptables/iptables-extensions.8.en.html
