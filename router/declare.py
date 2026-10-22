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
import shlex
import subprocess
import sys
from dataclasses import dataclass

SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"]


@dataclass(frozen=True)
class File:
    path: str
    content: bytes
    mode: int = 0o644


@dataclass(frozen=True)
class Spec:
    files: tuple[File, ...]
    # {stage} 替换为远端暂存目录，候选文件按原绝对路径放在其下
    validate: str
    reload: str
    verify: str
    # 该目录内未声明的文件视为多余，sync 时删除
    owned_dir: str | None = None


@dataclass(frozen=True)
class Plan:
    changed: tuple[File, ...]
    extra: tuple[str, ...]


def ssh(command: str, data: bytes | None = None) -> bytes:
    target = os.environ["ROUTER_SSH"]
    args = ["ssh", *SSH_OPTS, target, command] if data is not None else ["ssh", "-n", *SSH_OPTS, target, command]
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(f"远端命令失败：{command}\n{result.stdout.decode(errors='replace')}{result.stderr.decode(errors='replace')}")
        raise SystemExit(1)
    return result.stdout


def fingerprint(file: File) -> str:
    return f"{file.mode:o} {hashlib.sha256(file.content).hexdigest()}"


def remote_fingerprints(paths: list[str]) -> dict[str, str]:
    script = "".join(
        f"p={shlex.quote(p)}; if [ -f \"$p\" ]; then echo \"$(stat -c %a \"$p\") $(sha256sum < \"$p\" | cut -d' ' -f1)\"; else echo -; fi\n"
        for p in paths
    )
    return dict(zip(paths, ssh(script).decode().splitlines()))


def plan(spec: Spec) -> Plan:
    have = remote_fingerprints([f.path for f in spec.files])
    changed = tuple(f for f in spec.files if have[f.path] != fingerprint(f))
    extra: tuple[str, ...] = ()
    if spec.owned_dir:
        listing = ssh(f"ls -1A {shlex.quote(spec.owned_dir)} 2>/dev/null || true").decode().splitlines()
        declared = {f.path for f in spec.files}
        extra = tuple(sorted(f"{spec.owned_dir}/{n}" for n in listing if f"{spec.owned_dir}/{n}" not in declared))
    return Plan(changed, extra)


def show(spec: Spec, todo: Plan) -> None:
    for file in todo.changed:
        current = ssh(f"cat {shlex.quote(file.path)} 2>/dev/null || true")
        print(f"--- 差异：{file.path}（权限 {file.mode:o}）")
        try:
            before, after = current.decode(), file.content.decode()
        except UnicodeDecodeError:
            print(f"二进制内容不同，将替换（sha256 {hashlib.sha256(file.content).hexdigest()[:12]}）")
            continue
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
    if not todo.changed and not todo.extra:
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
        print(ssh(spec.reload).decode(), end="")
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
