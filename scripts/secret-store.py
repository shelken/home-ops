#!/usr/bin/env python3
"""BWS 项目里 JSON secret 的写侧工具：一个 secret 名下存一个 JSON 对象，按键增删改。

读侧（模板渲染）见 secret-inject.py；两者约定一致：名字在项目内必须唯一。
需要环境变量 BWS_ACCESS_TOKEN、BWS_PROJECT_ID。除 show 外永不打印 secret 值。

子命令见下方 COMMANDS 表，无参数运行会打印用法。
"""

import json
import os
import shlex
import subprocess
import sys
import tempfile
from collections.abc import Callable
from functools import cache
from pathlib import Path
from typing import NamedTuple, NoReturn

# BWS 单个 secret 值的长度上限
MAX_VALUE = 25000


class Secret(NamedTuple):
    id: str
    value: str


def die(msg: str) -> NoReturn:
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], what: str) -> str:
    # 失败信息只取 stderr，不回显 cmd：写操作的 argv 里带着 secret 值
    try:
        return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    except FileNotFoundError:
        die(f"'{cmd[0]}' 未安装或不在 PATH 中")
    except subprocess.CalledProcessError as e:
        die(f"{what} 失败: {e.stderr.strip()}")


@cache
def project_id() -> str:
    hints = {
        "BWS_ACCESS_TOKEN": "机器账号访问令牌，在 shell 里 export，不进仓库",
        "BWS_PROJECT_ID": "BWS 项目 ID，在仓库目录内由 mise.toml 的 [env] 提供，需激活 mise",
    }
    if missing := [name for name in hints if not os.environ.get(name)]:
        die(
            "缺少环境变量:\n"
            + "\n".join(f"  {name}  {hints[name]}" for name in missing)
        )
    return os.environ["BWS_PROJECT_ID"]


def listing() -> dict[str, list[Secret]]:
    out = run(
        ["bws", "secret", "list", project_id(), "-o", "json"], "bws 获取 secret 列表"
    )
    try:
        items = json.loads(out)
    except json.JSONDecodeError as e:
        die(f"bws secret list 输出不是合法 JSON: {e}")
    secrets: dict[str, list[Secret]] = {}
    for item in items:
        secrets.setdefault(item["key"], []).append(Secret(item["id"], item["value"]))
    return secrets


def lookup(name: str) -> Secret | None:
    matches = listing().get(name, [])
    if len(matches) > 1:
        die(f"BWS 项目中有 {len(matches)} 个同名 secret: {name}，请先去重")
    return matches[0] if matches else None


def require(name: str) -> Secret:
    secret = lookup(name)
    if secret is None:
        die(f"BWS 项目中找不到名为 {name} 的 secret")
    return secret


def parse_object(name: str, secret: Secret) -> dict:
    try:
        data = json.loads(secret.value)
    except json.JSONDecodeError as e:
        die(f"{name} 不是合法 JSON: {e}")
    if not isinstance(data, dict):
        die(f"{name} 不是 JSON 对象")
    # 重新序列化会改写数字（精度、指数），ESO 与本仓库也只约定字符串值，所以拒绝而不是悄悄改写
    if bad := sorted(k for k, v in data.items() if not isinstance(v, str)):
        die(f"{name} 含非字符串值的键 {', '.join(bad)}，工具不改写，请用 edit")
    return data


def dump(data: object) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2)


def put(name: str, existing: Secret | None, value: str) -> None:
    """所有写入的唯一出口：先验 JSON 与长度，再创建或更新。"""
    try:
        json.loads(value)
    except json.JSONDecodeError as e:
        die(f"写入内容不是合法 JSON，未写入: {e}")
    if len(value) > MAX_VALUE:
        die(f"{name} 的值长度 {len(value)} 超过 BWS 上限 {MAX_VALUE}，未写入")
    if existing is None:
        cmd = ["bws", "secret", "create", "-o", "none", "--", name, value, project_id()]
    else:
        cmd = ["bws", "secret", "edit", "-o", "none", f"--value={value}", existing.id]
    run(cmd, f"bws 写入 {name}")


def cmd_list() -> None:
    found = listing()
    for name in sorted(found):
        print(name)
    for name, items in sorted(found.items()):
        if len(items) > 1:
            print(f"警告: {len(items)} 个同名 secret: {name}", file=sys.stderr)


def cmd_show(name: str) -> None:
    print(require(name).value)


def cmd_keys(name: str) -> None:
    print(dump(sorted(parse_object(name, require(name)))))


def cmd_set_key(name: str, key: str, value: str) -> None:
    if not value:
        die("value 不能为空")
    existing = lookup(name)
    data = parse_object(name, existing) if existing else {}
    put(name, existing, dump(data | {key: value}))
    print(f"✓ {name} 的键 {key} 已写入")


def cmd_delete_key(name: str, key: str) -> None:
    secret = require(name)
    data = parse_object(name, secret)
    if key not in data:
        die(f"{name} 中不存在键 {key}")
    del data[key]
    put(name, secret, dump(data))
    print(f"✓ {name} 的键 {key} 已删除")


def cmd_edit(name: str) -> None:
    existing = lookup(name)
    before = existing.value if existing else "{}"
    fd, tmp = tempfile.mkstemp(prefix="secret-store-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(before + "\n")
        editor = shlex.split(os.environ.get("EDITOR") or "vim")
        try:
            code = subprocess.run([*editor, tmp]).returncode
        except FileNotFoundError:
            die(f"编辑器 '{editor[0]}' 未安装或不在 PATH 中")
        if code != 0:
            die("编辑器异常退出，未写入")
        after = Path(tmp).read_text().rstrip("\n")
    finally:
        Path(tmp).unlink(missing_ok=True)
    if after == before.rstrip("\n"):
        print("→ 未检测到变更，跳过")
        return
    if not after.strip():
        die("内容已清空，未写入")
    put(name, existing, after)
    print(f"✓ {name} 已更新")


def cmd_delete(name: str) -> None:
    secret = require(name)
    run(["bws", "secret", "delete", secret.id], f"bws 删除 {name}")
    print(f"✓ {name} 已删除")


class Command(NamedTuple):
    run: Callable[..., None]
    args: tuple[str, ...]
    desc: str


COMMANDS: dict[str, Command] = {
    "list": Command(cmd_list, (), "列出所有 secret 名称"),
    "show": Command(cmd_show, ("name",), "显示 secret 的值"),
    "keys": Command(cmd_keys, ("name",), "列出 JSON secret 的键名（不含值）"),
    "set-key": Command(
        cmd_set_key,
        ("name", "key", "value"),
        "设置 JSON secret 中的键（secret 不存在则创建）",
    ),
    "delete-key": Command(cmd_delete_key, ("name", "key"), "删除 JSON secret 中的键"),
    "edit": Command(
        cmd_edit,
        ("name",),
        "用 $EDITOR 编辑 JSON secret，内容有变化且为合法 JSON 才写入",
    ),
    "delete": Command(cmd_delete, ("name",), "删除整个 secret"),
}


def usage() -> str:
    lines = [
        f"  {name} {' '.join(f'<{a}>' for a in cmd.args)}".rstrip().ljust(32) + cmd.desc
        for name, cmd in COMMANDS.items()
    ]
    return f"用法: {Path(sys.argv[0]).name} <子命令> ...\n" + "\n".join(lines)


def main() -> None:
    argv = sys.argv[1:]
    cmd = COMMANDS.get(argv[0]) if argv else None
    if cmd is None or len(argv) - 1 != len(cmd.args):
        print(usage(), file=sys.stderr)
        sys.exit(2)
    project_id()
    cmd.run(*argv[1:])


if __name__ == "__main__":
    main()
