#!/usr/bin/env python3
"""渲染模板中的 azure://<vault>/<secret>[/<json_key>] 占位符。

用法:
  azure-inject.py print <file>    # 渲染到 stdout（管道场景，如 kubectl apply）
  azure-inject.py render <dir>    # 渲染目录下所有 *.tpl 到去掉 .tpl 后缀的同名文件（就地原子替换）

同一批文件中每个 <vault>/<secret> 只调用一次 az；无占位符的模板静默原样输出。
日志全部走 stderr，stdout 只有渲染结果。
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# 优先匹配 {{azure://...}} 包裹形式，避免裸匹配在包裹形式内提前截断；捕获组不含 azure:// 前缀
PLACEHOLDER = re.compile(r"\{\{azure://([^{}]+)\}\}|azure://([A-Za-z0-9._/-]+)")

_secret_cache: dict[tuple[str, str], str] = {}


def die(msg: str):
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(1)


def fetch_secret(vault: str, secret: str) -> str:
    key = (vault, secret)
    if key not in _secret_cache:
        print(f"获取: {vault}/{secret}", file=sys.stderr)
        try:
            result = subprocess.run(
                ["az", "keyvault", "secret", "show", "--vault-name", vault,
                 "--name", secret, "--query", "value", "-o", "tsv"],
                check=True, capture_output=True, text=True)
        except FileNotFoundError:
            die("'az' (Azure CLI) 未安装或不在 PATH 中")
        except subprocess.CalledProcessError as e:
            die(f"az 获取 {vault}/{secret} 失败: {e.stderr.strip()}")
        _secret_cache[key] = result.stdout.rstrip("\n")
    return _secret_cache[key]


def resolve(ref: str) -> str:
    vault, secret, *json_keys = ref.split("/", 2)
    value = fetch_secret(vault, secret)
    if json_keys:
        json_key = json_keys[0]
        try:
            data = json.loads(value)
        except json.JSONDecodeError as e:
            die(f"{vault}/{secret} 不是合法 JSON，无法取键 {json_key}: {e}")
        if not isinstance(data, dict) or json_key not in data:
            die(f"{vault}/{secret} 中不存在键 {json_key}")
        value = data[json_key]
        # 值为 null 时若静默写出 "null"，产物看似合法但配置错误，且不会中止
        if value is None:
            die(f"{vault}/{secret} 的键 {json_key} 值为 null")
        # 与 jq -r 行为一致：非字符串 JSON 值原样序列化
        if not isinstance(value, str):
            value = json.dumps(value)
    return value


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
