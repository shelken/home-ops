#!/usr/bin/env python3
"""渲染模板中的多来源占位符，裸写或 {{scheme://...}} 包裹均可。

来源:
  azure://<vault>/<secret>[/<json_key>]  Azure KeyVault，调用 az
  bws://<name>[/<json_key>]              Bitwarden Secrets Manager，调用 bws，
                                         需要环境变量 BWS_ACCESS_TOKEN、BWS_PROJECT_ID

用法:
  secret-inject.py print <file>    # 渲染到 stdout（管道场景，如 kubectl apply）
  secret-inject.py render <dir>    # 渲染目录下所有 *.tpl 到去掉 .tpl 后缀的同名文件（就地原子替换）

同一批文件中每个引用只获取一次，bws 整个项目只调用一次 secret list；
无占位符的模板静默原样输出。日志全部走 stderr，stdout 只有渲染结果，任何日志都不含 secret 值。
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from collections.abc import Callable
from functools import cache
from pathlib import Path
from typing import NamedTuple, NoReturn


def die(msg: str) -> NoReturn:
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], what: str) -> str:
    try:
        return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    except FileNotFoundError:
        die(f"'{cmd[0]}' 未安装或不在 PATH 中")
    except subprocess.CalledProcessError as e:
        die(f"{what} 失败: {e.stderr.strip()}")


@cache
def fetch_azure(vault: str, secret: str) -> str:
    print(f"获取: azure://{vault}/{secret}", file=sys.stderr)
    out = run(
        ["az", "keyvault", "secret", "show", "--vault-name", vault]
        + ["--name", secret, "--query", "value", "-o", "tsv"],
        f"az 获取 {vault}/{secret}",
    )
    return out.rstrip("\n")


@cache
def bws_secrets() -> dict[str, list[str]]:
    """整个项目只列一次；同名 secret 在 BWS 中合法，所以每个名字保留全部值。"""
    project = os.environ.get("BWS_PROJECT_ID")
    if not project:
        die("未设置环境变量 BWS_PROJECT_ID（BWS 项目 ID）")
    if not os.environ.get("BWS_ACCESS_TOKEN"):
        die("未设置环境变量 BWS_ACCESS_TOKEN（BWS 机器账号访问令牌）")
    print("获取: bws secret list", file=sys.stderr)
    out = run(["bws", "secret", "list", project, "-o", "json"], "bws 获取 secret 列表")
    try:
        items = json.loads(out)
    except json.JSONDecodeError as e:
        die(f"bws secret list 输出不是合法 JSON: {e}")
    secrets: dict[str, list[str]] = {}
    for item in items:
        secrets.setdefault(item["key"], []).append(item["value"])
    return secrets


def fetch_bws(name: str) -> str:
    matches = bws_secrets().get(name)
    if not matches:
        die(f"BWS 项目中找不到名为 {name} 的 secret")
    if len(matches) > 1:
        die(f"BWS 项目中有 {len(matches)} 个同名 secret: {name}，请先去重")
    return matches[0]


class Source(NamedTuple):
    fetch: Callable[..., str]
    # 定位符段数；其后的路径整体作为 json_key
    locator_parts: int


SOURCES: dict[str, Source] = {
    "azure": Source(fetch_azure, 2),
    "bws": Source(fetch_bws, 1),
}

_REF_HEAD = "(?:" + "|".join(map(re.escape, SOURCES)) + ")://"
# 优先匹配 {{scheme://...}} 包裹形式，避免裸匹配在包裹形式内提前截断；捕获组含 scheme 前缀
PLACEHOLDER = re.compile(
    r"\{\{(" + _REF_HEAD + r"[^{}]+)\}\}|(" + _REF_HEAD + r"[A-Za-z0-9._/-]+)"
)


def parse_ref(ref: str) -> tuple[str, tuple[str, ...], str | None]:
    scheme, _, rest = ref.partition("://")
    n = SOURCES[scheme].locator_parts
    parts = rest.split("/", n)
    if len(parts) < n:
        die(f"占位符不完整: {ref}")
    json_key = parts[n] if len(parts) > n else None
    return scheme, tuple(parts[:n]), json_key


def extract_json_key(label: str, value: str, json_key: str) -> str:
    try:
        data = json.loads(value)
    except json.JSONDecodeError as e:
        die(f"{label} 不是合法 JSON，无法取键 {json_key}: {e}")
    if not isinstance(data, dict) or json_key not in data:
        die(f"{label} 中不存在键 {json_key}")
    value = data[json_key]
    # 值为 null 时若静默写出 "null"，产物看似合法但配置错误，且不会中止
    if value is None:
        die(f"{label} 的键 {json_key} 值为 null")
    # 与 jq -r 行为一致：非字符串 JSON 值原样序列化
    if not isinstance(value, str):
        value = json.dumps(value)
    return value


def resolve(ref: str) -> str:
    scheme, locator, json_key = parse_ref(ref)
    value = SOURCES[scheme].fetch(*locator)
    if json_key is None:
        return value
    return extract_json_key(f"{scheme}://{'/'.join(locator)}", value, json_key)


def render_text(text: str) -> str:
    return PLACEHOLDER.sub(lambda m: resolve(m.group(1) or m.group(2)), text)


def render_file(tpl: Path):
    out = tpl.with_suffix("")
    print(f"渲染: {tpl} -> {out}", file=sys.stderr)
    content = render_text(tpl.read_text())
    fd, tmp = tempfile.mkstemp(dir=out.parent, prefix=out.name + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        # mkstemp 固定 0600，会让 rsync 同步出非 root 容器读不了的配置；继承模板权限
        os.chmod(tmp, tpl.stat().st_mode & 0o777)
        os.replace(tmp, out)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def main():
    args = sys.argv[1:]
    if len(args) != 2 or args[0] not in ("print", "render"):
        die(f"用法: {sys.argv[0]} print <file> | render <dir>")
    mode, target = args
    if mode == "print":
        path = Path(target)
        if not path.is_file():
            die(f"文件不存在: {path}")
        sys.stdout.write(render_text(path.read_text()))
        return
    root = Path(target)
    if not root.is_dir():
        die(f"目录不存在: {root}")
    templates = sorted(p for p in root.rglob("*.tpl") if p.is_file())
    if not templates:
        die(f"目录下没有 *.tpl 文件: {root}")
    for tpl in templates:
        render_file(tpl)


if __name__ == "__main__":
    main()
