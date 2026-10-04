#!/usr/bin/env python3
"""下发 home-ops 拥有的路由器 dnsmasq 配置。"""

from __future__ import annotations

import difflib
import os
import pathlib
import shlex
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
CONF_SRC = HERE / "conf.d"
HOSTS_SRC = HERE / "dnsmasq-int.hosts"

BASE_CONF = os.environ["DNS_BASE_CONF"]
CONF_DST = os.environ["DNS_MANAGED_CONF_DIR"]
HOSTS_DST = os.environ["DNS_HOSTS_DST"]
CONF_SUFFIX = ".conf"
MANAGED_BEGIN = "# BEGIN home-ops dnsmasq"
MANAGED_END = "# END home-ops dnsmasq"

SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]


def _host() -> str:
    return os.environ["ROUTER_SSH"]


def ssh_read(*args: str) -> list[str]:
    """构造不占用 stdin 的远端命令。"""
    return ["ssh", "-n", *SSH_OPTS, _host(), *args]


def ssh_write(*args: str) -> list[str]:
    """构造需要 stdin 的远端命令。"""
    return ["ssh", *SSH_OPTS, _host(), *args]


def run(args: list[str], text: str | None = None) -> str:
    result = subprocess.run(args, input=text, text=True, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(f"命令失败：{' '.join(args)}\n{result.stdout}{result.stderr}")
        raise SystemExit(1)
    return result.stdout


def render() -> dict[str, str]:
    values = {
        "MAIN_DOMAIN": os.environ["MAIN_DOMAIN"],
        "INTERNAL_DOMAIN": os.environ["INTERNAL_DOMAIN"],
        "DNS_GATEWAY": os.environ["DNS_GATEWAY"],
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
    listing = run(ssh_read(f"ls -1 {shlex.quote(CONF_DST)} 2>/dev/null || true"))
    return {name for name in listing.split() if name.endswith(CONF_SUFFIX)}


def remote_text(path: str) -> str:
    return run(ssh_read(f"cat {shlex.quote(path)} 2>/dev/null || true"))


def remote_addnhosts() -> set[str]:
    values = run(ssh_read("uci -q get dhcp.@dnsmasq[0].addnhosts || true"))
    return set(values.split())


def managed_base_conf(current: str) -> str:
    directive = f"conf-dir={CONF_DST},*.conf"
    block = f"{MANAGED_BEGIN}\n{directive}\n{MANAGED_END}\n"
    lines = current.splitlines(keepends=True)
    begin = [i for i, line in enumerate(lines) if line.rstrip("\r\n") == MANAGED_BEGIN]
    end = [i for i, line in enumerate(lines) if line.rstrip("\r\n") == MANAGED_END]

    if not begin and not end:
        prefix = current
        if prefix and not prefix.endswith("\n"):
            prefix += "\n"
        if prefix and not prefix.endswith("\n\n"):
            prefix += "\n"
        return prefix + block
    if len(begin) != 1 or len(end) != 1 or begin[0] >= end[0]:
        raise SystemExit(f"{BASE_CONF} 的 home-ops 标记块损坏，需要人工修复")
    return "".join(lines[: begin[0]]) + block + "".join(lines[end[0] + 1 :])


def show_diff(name: str, current: str, wanted: str) -> bool:
    display_name = name.lstrip("/")
    if current == wanted:
        return False
    print(f"--- 差异：{name}")
    sys.stdout.writelines(
        difflib.unified_diff(
            current.splitlines(keepends=True),
            wanted.splitlines(keepends=True),
            fromfile=f"路由器/{display_name}",
            tofile=f"仓库/{display_name}",
        )
    )
    return True


def do_diff() -> int:
    wanted = render()
    current_base = remote_text(BASE_CONF)
    changed = show_diff(
        f"{BASE_CONF} 中的 home-ops 标记块",
        current_base,
        managed_base_conf(current_base),
    )

    have = remote_conf_names()
    for name in sorted(wanted):
        changed |= show_diff(name, remote_text(f"{CONF_DST}/{name}"), wanted[name])
    for name in sorted(have - set(wanted)):
        changed = True
        print(f"--- home-ops 专用目录多余：{name}（sync 会删除）")

    if HOSTS_DST not in remote_addnhosts():
        changed = True
        print(f"--- UCI 缺少 home-ops 条目：addnhosts={HOSTS_DST}")
    changed |= show_diff("int.hosts", remote_text(HOSTS_DST), HOSTS_SRC.read_text())

    if not changed:
        print("路由器 dnsmasq 的 home-ops 配置与仓库一致，无差异")
    return 0


def write_remote(path: str, text: str) -> None:
    run(ssh_write(f"cat > {shlex.quote(path)}"), text=text)


def write_remote_atomic(path: str, text: str, *, preserve_mode: bool = False) -> None:
    target = pathlib.PurePosixPath(path)
    temporary = f"{path}.home-ops.new"
    run(ssh_read(f"mkdir -p {shlex.quote(str(target.parent))}; rm -f {shlex.quote(temporary)}"))
    if preserve_mode:
        run(ssh_read(f"cp -p {shlex.quote(path)} {shlex.quote(temporary)}"))
    write_remote(temporary, text)
    run(ssh_read(f"mv -f {shlex.quote(temporary)} {shlex.quote(path)}"))


def validate(wanted: dict[str, str]) -> None:
    temporary = f"/tmp/home-ops-dnsmasq-{os.getpid()}"
    try:
        run(ssh_read(f"rm -rf {shlex.quote(temporary)}; mkdir -p {shlex.quote(temporary)}"))
        for name, text in wanted.items():
            write_remote(f"{temporary}/{name}", text)
        write_remote(f"{temporary}/int.hosts", HOSTS_SRC.read_text())
        confdir = shlex.quote(f"{temporary},*.conf")
        hosts = shlex.quote(f"{temporary}/int.hosts")
        run(
            ssh_read(
                f"dnsmasq --test --conf-file=/dev/null "
                f"--conf-dir={confdir} --addn-hosts={hosts}"
            )
        )
    finally:
        run(ssh_read(f"rm -rf {shlex.quote(temporary)}"))


def do_sync() -> int:
    wanted = render()
    validate(wanted)

    run(
        ssh_read(
            f"mkdir -p {shlex.quote(CONF_DST)} "
            f"{shlex.quote(str(pathlib.PurePosixPath(HOSTS_DST).parent))}"
        )
    )
    for name, text in sorted(wanted.items()):
        path = f"{CONF_DST}/{name}"
        if remote_text(path) != text:
            write_remote_atomic(path, text)
            print(f"已下发：{path}")

    for name in sorted(remote_conf_names() - set(wanted)):
        run(ssh_read(f"rm -f {shlex.quote(f'{CONF_DST}/{name}')}"))
        print(f"已删除 home-ops 专用目录中的多余文件：{name}")

    if remote_text(HOSTS_DST) != HOSTS_SRC.read_text():
        write_remote_atomic(HOSTS_DST, HOSTS_SRC.read_text())
        print(f"已下发：{HOSTS_DST}")

    current_base = remote_text(BASE_CONF)
    wanted_base = managed_base_conf(current_base)
    if current_base != wanted_base:
        write_remote_atomic(BASE_CONF, wanted_base, preserve_mode=True)
        print(f"已更新：{BASE_CONF} 中的 home-ops 标记块")

    if HOSTS_DST not in remote_addnhosts():
        run(
            ssh_read(
                f"uci add_list dhcp.@dnsmasq[0].addnhosts={shlex.quote(HOSTS_DST)}; "
                "uci commit dhcp"
            )
        )
        print(f"已添加 UCI 条目：addnhosts={HOSTS_DST}")

    run(ssh_read("/etc/init.d/dnsmasq restart; pidof dnsmasq >/dev/null"))

    name = next(
        (
            line.split()[1]
            for line in HOSTS_SRC.read_text().splitlines()
            if line.strip() and not line.startswith("#")
        ),
        None,
    )
    if name:
        probe = run(ssh_read(f"nslookup {shlex.quote(name)} 127.0.0.1 2>&1 || true"))
        if "Address" not in probe:
            sys.stderr.write(f"dnsmasq 未返回 {name}：\n{probe}")
            return 1
        print(probe.strip())
    print("已下发 home-ops 配置并重启 dnsmasq")
    return 0


def main() -> int:
    action, *rest = sys.argv[1:] or ["diff"]
    if rest:
        raise SystemExit("用法：declare.py [diff|sync]")
    if action == "diff":
        return do_diff()
    if action == "sync":
        return do_sync()
    raise SystemExit("用法：declare.py [diff|sync]")


if __name__ == "__main__":
    sys.exit(main())
