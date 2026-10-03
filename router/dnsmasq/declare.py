#!/usr/bin/env python3
"""路由器 dnsmasq 的声明式下发。

约定：本目录 `conf.d/` 的渲染结果等于路由器 `CONF_DST` 的内容，
`dnsmasq-int.hosts` 等于 `HOSTS_DST`。分流规则只以文件表达，
不使用 `uci set` / `add_list`；`confdir` 由 `task router:dns:bootstrap`
一次性引导，之后所有变更都是文件与 reload。
"""

from __future__ import annotations

import difflib
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
CONF_SRC = HERE / "conf.d"
HOSTS_SRC = HERE / "dnsmasq-int.hosts"

# 远端落地路径由 taskfile 经 env 传入：同一路径在仓库里只声明一次
CONF_DST = os.environ["DNS_CONF_DIR"]
HOSTS_DST = os.environ["DNS_HOSTS_DST"]
CONF_SUFFIX = ".conf"

SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]


def _host() -> str:
    return os.environ["ROUTER_SSH"]


def ssh_read(*args: str) -> list[str]:
    """构造不占用 stdin 的远端只读命令。"""
    return ["ssh", "-n", *SSH_OPTS, _host(), *args]


def ssh_write(*args: str) -> list[str]:
    """构造需要 stdin 的远端命令（不能带 -n）。"""
    return ["ssh", *SSH_OPTS, _host(), *args]


def run(args: list[str], text: str | None = None) -> str:
    result = subprocess.run(args, input=text, text=True, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(f"命令失败：{' '.join(args)}\n{result.stderr}")
        raise SystemExit(1)
    return result.stdout


def render() -> dict[str, str]:
    values = {
        "MAIN_DOMAIN": os.environ["MAIN_DOMAIN"],
        "INTERNAL_DOMAIN": os.environ["INTERNAL_DOMAIN"],
        "DNS_GATEWAY": os.environ["DNS_GATEWAY"],
        "DNS_FALLBACK": os.environ["DNS_FALLBACK"],
    }
    files: dict[str, str] = {}
    for path in sorted(CONF_SRC.iterdir()):
        if path.name.endswith(".conf.tpl"):
            name = path.name[: -len(".tpl")]
        elif path.name.endswith(CONF_SUFFIX):
            name = path.name
        else:
            continue
        text = path.read_text()
        for key, value in values.items():
            text = text.replace("${" + key + "}", value)
        leftover = [line for line in text.splitlines() if "${" in line]
        if leftover:
            raise SystemExit(f"{path.name} 渲染后仍有未替换的变量：{leftover}")
        files[name] = text
    if not files:
        raise SystemExit(f"{CONF_SRC} 下没有可下发的配置")
    return files


def remote_conf_names() -> set[str]:
    listing = run(ssh_read(f"ls -1 {CONF_DST} 2>/dev/null || true"))
    return {name for name in listing.split() if name.endswith(CONF_SUFFIX)}


def remote_text(path: str) -> str:
    return run(ssh_read(f"cat {path} 2>/dev/null || true"))


def require_confdir() -> None:
    """confdir 指向仓库约定的持久目录，是唯一的一次性引导。"""
    current = run(ssh_read("uci -q get dhcp.@dnsmasq[0].confdir || true")).strip()
    if current != CONF_DST:
        raise SystemExit(
            f"路由器 confdir 当前为 {current or '<未设置>'}，需要一次性引导为 {CONF_DST}：\n"
            f"  ssh <路由器> \"uci set dhcp.@dnsmasq[0].confdir='{CONF_DST}'; "
            "uci commit dhcp; /etc/init.d/dnsmasq restart\"\n"
            "该引导只做一次；其后所有规则都由本仓库文件声明。"
        )


def show_diff(name: str, current: str, wanted: str) -> bool:
    if current == wanted:
        return False
    print(f"--- 差异：{name}")
    sys.stdout.writelines(
        difflib.unified_diff(
            current.splitlines(keepends=True),
            wanted.splitlines(keepends=True),
            fromfile=f"路由器/{name}",
            tofile=f"仓库/{name}",
        )
    )
    return True


def do_diff() -> int:
    require_confdir()
    wanted = render()
    have = remote_conf_names()
    changed = False
    for name in sorted(wanted):
        changed |= show_diff(name, remote_text(f"{CONF_DST}/{name}"), wanted[name])
    for name in sorted(have - set(wanted)):
        changed = True
        print(f"--- 路由器多余：{name}（sync 会删除）")
    changed |= show_diff("int.hosts", remote_text(HOSTS_DST), HOSTS_SRC.read_text())
    if not changed:
        print("路由器 dnsmasq 声明与仓库一致，无差异")
    # diff 只用于展示与 stderr 提示，始终成功退出，避免作为 sync 的依赖时中断
    return 0


def write_remote(path: str, text: str) -> None:
    run(ssh_write(f"cat > {path}"), text=text)


def do_sync() -> int:
    require_confdir()
    wanted = render()
    run(ssh_read(f"mkdir -p {CONF_DST} {pathlib.PurePosixPath(HOSTS_DST).parent}"))

    for name, text in sorted(wanted.items()):
        if remote_text(f"{CONF_DST}/{name}") != text:
            write_remote(f"{CONF_DST}/{name}", text)
            print(f"已下发：{name}")

    if remote_text(HOSTS_DST) != HOSTS_SRC.read_text():
        write_remote(HOSTS_DST, HOSTS_SRC.read_text())
        print("已下发：int.hosts")

    for name in sorted(remote_conf_names() - set(wanted)):
        run(ssh_read(f"rm -f {CONF_DST}/{name}"))
        print(f"已删除多余文件：{name}")

    run(ssh_read("/etc/init.d/dnsmasq reload"))

    # 用路由器本机查询一个自举名，确认 dnsmasq 真的重读了声明
    name = next(
        (line.split()[1] for line in HOSTS_SRC.read_text().splitlines() if line.strip() and not line.startswith("#")),
        None,
    )
    if name:
        probe = run(ssh_read(f"nslookup {name} 127.0.0.1 2>&1 || true"))
        if "Address" not in probe:
            sys.stderr.write(f"dnsmasq 未返回 {name}：\n{probe}")
            return 1
        print(probe.strip())
    print("已下发声明并重载 dnsmasq")
    return 0


def main() -> int:
    action, *rest = sys.argv[1:] or ["diff"]
    if rest:
        raise SystemExit("用法：router-dns-declare.py [diff|sync]")
    if action == "diff":
        return do_diff()
    if action == "sync":
        return do_sync()
    raise SystemExit("用法：router-dns-declare.py [diff|sync]")


if __name__ == "__main__":
    sys.exit(main())
