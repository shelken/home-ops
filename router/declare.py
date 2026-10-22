#!/usr/bin/env python3
"""把路由器上由 home-ops 管理的文件收敛到仓库声明。

用法：declare.py <功能> diff|sync，功能即 router/<功能>/spec.py 提供的 spec()。
diff 严格只读；sync 先在暂存目录校验全部候选文件，再原子下发变化、删除独占目录中的多余文件、生效并验证。
"""

from __future__ import annotations

import difflib
import hashlib
import importlib
import os
import re
import shlex
import stat
import subprocess
import sys
from dataclasses import dataclass

SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]
# 订阅与节点链接携带凭据；agent 也会运行 diff，输出一律脱敏
SECRET_URL = re.compile(r"\b([a-z][a-z0-9+.-]*)://[^\s'\"]+")


def redact(text: str) -> str:
    return SECRET_URL.sub(
        lambda m: f"{m[1]}://<已隐藏#{hashlib.sha256(m[0].encode()).hexdigest()[:8]}>", text
    )


@dataclass(frozen=True)
class File:
    path: str
    content: bytes
    mode: int = 0o644
    # 该文件变化时代替 Spec.reload，例如二进制变化需要完整重启
    reload: str | None = None
    # 含凭据：diff 与报错中的链接一律脱敏，只能用 sops 查看原文
    sensitive: bool = False


@dataclass(frozen=True)
class Service:
    """/etc/init.d 服务的期望状态：enabled 为开机自启且运行，否则停止且禁用。"""

    name: str
    enabled: bool


@dataclass(frozen=True)
class Spec:
    files: tuple[File, ...]
    # {stage} 替换为远端暂存目录，候选文件按原绝对路径放在其下
    validate: str
    reload: str
    verify: str
    # 该目录内未声明的文件视为多余，sync 时删除
    owned_dir: str | None = None
    # 按顺序收敛，需先停的服务排在前面
    services: tuple[Service, ...] = ()


@dataclass(frozen=True)
class Plan:
    changed: tuple[File, ...]
    extra: tuple[str, ...]
    services: tuple[Service, ...]

    def empty(self) -> bool:
        return not (self.changed or self.extra or self.services)


def ssh(command: str, data: bytes | None = None) -> bytes:
    target = os.environ["DECLARE_SSH"]
    args = ["ssh", *SSH_OPTS, target, command] if data is not None else ["ssh", "-n", *SSH_OPTS, target, command]
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(redact(f"远端命令失败：{command}\n{result.stdout.decode(errors='replace')}{result.stderr.decode(errors='replace')}"))
        raise SystemExit(1)
    return result.stdout


def fingerprint(file: File) -> str:
    return f"{stat.filemode(stat.S_IFREG | file.mode)} {hashlib.sha256(file.content).hexdigest()}"


def remote_fingerprints(paths: list[str]) -> dict[str, str]:
    # 旁路由的精简 busybox 没有 stat，权限取 ls -l 的模式串
    script = "".join(
        f"p={shlex.quote(p)}; if [ -f \"$p\" ]; then echo \"$(ls -l \"$p\" | cut -c1-10) $(sha256sum < \"$p\" | cut -d' ' -f1)\"; else echo -; fi\n"
        for p in paths
    )
    return dict(zip(paths, ssh(script).decode().splitlines()))


def remote_services(names: list[str]) -> dict[str, bool | None]:
    script = "".join(
        f"s=/etc/init.d/{shlex.quote(n)}; if [ ! -x $s ]; then echo off; "
        "elif $s enabled && $s running; then echo on; "
        "elif ! $s enabled && ! $s running; then echo off; else echo partial; fi\n"
        for n in names
    )
    states = {"on": True, "off": False, "partial": None}
    return {n: states[s] for n, s in zip(names, ssh(script).decode().splitlines())}


def plan(spec: Spec) -> Plan:
    have = remote_fingerprints([f.path for f in spec.files])
    changed = tuple(f for f in spec.files if have[f.path] != fingerprint(f))
    extra: tuple[str, ...] = ()
    if spec.owned_dir:
        listing = ssh(f"ls -1A {shlex.quote(spec.owned_dir)} 2>/dev/null || true").decode().splitlines()
        declared = {f.path for f in spec.files}
        extra = tuple(sorted(f"{spec.owned_dir}/{n}" for n in listing if f"{spec.owned_dir}/{n}" not in declared))
    states = remote_services([s.name for s in spec.services]) if spec.services else {}
    services = tuple(s for s in spec.services if states[s.name] != s.enabled)
    return Plan(changed, extra, services)


def show(spec: Spec, todo: Plan) -> None:
    for file in todo.changed:
        print(f"--- 差异：{file.path}（权限 {file.mode:o}）")
        try:
            after = file.content.decode()
        except UnicodeDecodeError:
            # 二进制不做逐行对比，也就不必把远端文件（dae 约 33MB）拉回本地
            print(f"二进制内容不同，将替换（sha256 {hashlib.sha256(file.content).hexdigest()[:12]}）")
            continue
        before = ssh(f"cat {shlex.quote(file.path)} 2>/dev/null || true").decode(errors="replace")
        if file.sensitive:
            before, after = redact(before), redact(after)
            print("链接已脱敏，哈希不同即链接有变化；原文用 sops 查看")
        name = file.path.lstrip("/")
        sys.stdout.writelines(
            difflib.unified_diff(
                before.splitlines(keepends=True),
                after.splitlines(keepends=True),
                fromfile=f"路由器/{name}",
                tofile=f"仓库/{name}",
            )
        )
    for path in todo.extra:
        print(f"--- 多余：{path}（sync 会删除）")
    for service in todo.services:
        print(f"--- 服务 {service.name}：将{'启用并启动' if service.enabled else '停止并禁用'}")
    if todo.empty():
        print("路由器与仓库一致，无差异")


def write(path: str, file: File) -> None:
    quoted = shlex.quote(path)
    ssh(f"mkdir -p {shlex.quote(os.path.dirname(path))} && cat > {quoted} && chmod {file.mode:o} {quoted}", file.content)


def validate(spec: Spec) -> None:
    stage = f"/tmp/home-ops-declare-{os.getpid()}"
    try:
        for file in spec.files:
            write(f"{stage}{file.path}", file)
        print(ssh(spec.validate.replace("{stage}", stage)).decode(), end="")
    finally:
        ssh(f"rm -rf {shlex.quote(stage)}")


def sync(spec: Spec) -> None:
    todo = plan(spec)
    if todo.changed or todo.extra:
        validate(spec)
    for file in todo.changed:
        write(f"{file.path}.home-ops.new", file)
        ssh(f"mv -f {shlex.quote(file.path + '.home-ops.new')} {shlex.quote(file.path)}")
        print(f"已下发：{file.path}")
    for path in todo.extra:
        ssh(f"rm -rf {shlex.quote(path)}")
        print(f"已删除多余：{path}")
    for service in todo.services:
        init = f"/etc/init.d/{shlex.quote(service.name)}"
        ssh(f"{init} enable && {init} start" if service.enabled else f"[ ! -x {init} ] || {{ {init} stop; {init} disable; }}")
        print(f"服务 {service.name}：已{'启用并启动' if service.enabled else '停止并禁用'}")
    # 本次启停过服务即已加载新文件，不再重复生效
    if (todo.changed or todo.extra) and not todo.services:
        print(ssh(next((f.reload for f in todo.changed if f.reload), spec.reload)).decode(), end="")
    print(ssh(spec.verify).decode(), end="")


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[2] not in ("diff", "sync"):
        raise SystemExit("用法：declare.py <功能> diff|sync")
    feature, action = sys.argv[1:]
    spec = importlib.import_module(f"{feature}.spec").spec()
    if action == "diff":
        show(spec, plan(spec))
    else:
        sync(spec)
    return 0


if __name__ == "__main__":
    sys.exit(main())
