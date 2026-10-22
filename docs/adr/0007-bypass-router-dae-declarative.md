---
date: 2026-10-22
status: accepted
---

# 旁路由用上游 release 的 dae 取代 daed，配置由仓库声明式下发

旁路由的透明代理从 daed 换成 dae。dae 的二进制、init 脚本和整份配置都由 `task router:dae:sync` 从仓库下发。daed 把配置存在 SQLite 里，Git 管不到，postmortem 010 那次 UI 状态和运行状态不一致也是这个原因。dae 二进制用上游 release，版本钉在 `router/dae/version.yaml`，由 Renovate 升级。不用 opkg 包，因为 ImmortalWrt 24.10 稳定分支禁止大版本升级，包停在 1.0.0，比 daed 内嵌的内核还旧。

## Considered Options

- opkg 的 dae 1.0.0：会降级，比 daed 内嵌内核落后 77 个提交
- 把上游二进制打进 ImageBuilder 固件：每次升级都要重新刷机
- QiuSimons/luci-app-dae：源码来自 `olicesx/dae` fork，不是上游
- 配置用模板加 AKV 占位符：文件里超过一半是内网地址、MAC 白名单、私有域名，逐项换占位符后模板读不懂，所以整份用 SOPS 加密

## Consequences

- 不再有 Web UI。切换节点、改规则都要改仓库再执行 sync
- opkg 升级 dae 包会覆盖 `/usr/bin/dae` 和 `/etc/init.d/dae`，下一次 sync 会检测到差异并换回来
- dae 不会自动刷新订阅，init 脚本另起一个 procd 实例，每 6 小时执行一次 `hot_reload`
- 回滚：在 `router/dae/spec.py` 里对调 daed 和 dae 的期望状态，然后执行 sync
