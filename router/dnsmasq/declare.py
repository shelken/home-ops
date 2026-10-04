#!/usr/bin/env python3
"""下发 home-ops 独占的路由器 dnsmasq 配置目录。"""

from __future__ import annotations

import difflib
import os
import pathlib
import shlex
import subprocess
import sys
from string import Template

HERE = pathlib.Path(__file__).resolve().parent
CONF_SRC = HERE / "conf.d"
HOSTS_SRC = HERE / "dnsmasq-int.hosts"

CONF_DST = os.environ["DNS_MANAGED_CONF_DIR"]
HOSTS_NAME = "int.hosts"
HOSTS_DST = f"{CONF_DST}/{HOSTS_NAME}"

ROUTER_SSH = os.environ["ROUTER_SSH"]
SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]


def ssh_read(*args: str) -> list[str]:
    """构造不占用 stdin 的远端命令。"""
    return ["ssh", "-n", *SSH_OPTS, ROUTER_SSH, *args]


def ssh_write(*args: str) -> list[str]:
    """构造需要 stdin 的远端命令。"""
    return ["ssh", *SSH_OPTS, ROUTER_SSH, *args]


def run(args: list[str], text: str | None = None) -> str:
    result = subprocess.run(args, input=text, text=True, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(f"命令失败：{' '.join(args)}\n{result.stdout}{result.stderr}")
        raise SystemExit(1)
    return result.stdout


def render_configs(hosts_path: str) -> dict[str, str]:
    values = {
        "MAIN_DOMAIN": os.environ["MAIN_DOMAIN"],
        "INTERNAL_DOMAIN": os.environ["INTERNAL_DOMAIN"],
        "DNS_GATEWAY": os.environ["DNS_GATEWAY"],
        "DNS_HOSTS_FILE": hosts_path,
    }
    files: dict[str, str] = {}
    for path in sorted(CONF_SRC.glob("*.conf.tpl")):
        name = path.name.removesuffix(".tpl")
        files[name] = Template(path.read_text()).substitute(values)
    if not files:
        raise SystemExit(f"{CONF_SRC} 下没有可下发的配置")
    return files


def desired_files() -> dict[str, str]:
    return {**render_configs(HOSTS_DST), HOSTS_NAME: HOSTS_SRC.read_text()}


def remote_names() -> set[str]:
    listing = run(ssh_read(f"ls -1A {shlex.quote(CONF_DST)} 2>/dev/null || true"))
    return set(listing.splitlines())


def remote_text(path: str) -> str:
    return run(ssh_read(f"cat {shlex.quote(path)} 2>/dev/null || true"))


def show_diff(path: str, current: str, wanted: str) -> bool:
    if current == wanted:
        return False
    display_name = path.lstrip("/")
    print(f"--- 差异：{path}")
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
    wanted = desired_files()
    have = remote_names()
    changed = False

    for name, text in sorted(wanted.items()):
        changed |= show_diff(f"{CONF_DST}/{name}", remote_text(f"{CONF_DST}/{name}"), text)
    for name in sorted(have - set(wanted)):
        changed = True
        print(f"--- home-ops 专用目录多余：{name}（sync 会删除）")

    if not changed:
        print("路由器 dnsmasq 的 home-ops 专用目录与仓库一致，无差异")
    return 0


def write_remote(path: str, text: str) -> None:
    run(ssh_write(f"cat > {shlex.quote(path)}"), text=text)


def write_remote_atomic(path: str, text: str) -> None:
    temporary = f"{path}.home-ops.new"
    write_remote(temporary, text)
    run(ssh_read(f"mv -f {shlex.quote(temporary)} {shlex.quote(path)}"))


def validate() -> None:
    temporary = f"/tmp/home-ops-dnsmasq-{os.getpid()}"
    files = {
        **render_configs(f"{temporary}/{HOSTS_NAME}"),
        HOSTS_NAME: HOSTS_SRC.read_text(),
    }
    try:
        run(ssh_read(f"rm -rf {shlex.quote(temporary)}; mkdir -p {shlex.quote(temporary)}"))
        for name, text in files.items():
            write_remote(f"{temporary}/{name}", text)
        run(
            ssh_read(
                "dnsmasq --test --conf-file=/dev/null "
                f"--conf-dir={shlex.quote(f'{temporary},*.conf')}"
            )
        )
    finally:
        run(ssh_read(f"rm -rf {shlex.quote(temporary)}"))


def do_sync() -> int:
    wanted = desired_files()
    validate()

    run(ssh_read(f"mkdir -p {shlex.quote(CONF_DST)}"))
    for name, text in sorted(wanted.items()):
        path = f"{CONF_DST}/{name}"
        if remote_text(path) != text:
            write_remote_atomic(path, text)
            print(f"已下发：{path}")

    for name in sorted(remote_names() - set(wanted)):
        run(ssh_read(f"rm -rf {shlex.quote(f'{CONF_DST}/{name}')}"))
        print(f"已删除 home-ops 专用目录中的多余内容：{name}")

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
    print("已下发 home-ops 专用目录并重启 dnsmasq")
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
