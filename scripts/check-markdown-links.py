#!/usr/bin/env python3
"""校验 Markdown 里指向仓库内路径的相对链接。

只回答一个问题：这个相对路径在仓库里存在吗。外链需要网络、锚点需要解析标题，
都不在这里检查。围栏代码块里的链接是示例，跳过。
"""

from __future__ import annotations

import pathlib
import re
import sys

LINK = re.compile(r"!?\[[^\]]*\]\(\s*([^)\s]+)")
FENCE = re.compile(r"^\s*(```|~~~)")
EXTERNAL = ("http://", "https://", "mailto:", "data:", "//", "#")
ROOT = pathlib.Path(__file__).resolve().parent.parent


def targets(text: str) -> list[str]:
    found: list[str] = []
    inside_fence = False
    for line in text.splitlines():
        if FENCE.match(line):
            inside_fence = not inside_fence
            continue
        if not inside_fence:
            found += LINK.findall(line)
    return found


def resolve(markdown: pathlib.Path, target: str) -> pathlib.Path:
    """`/x` 是相对仓库根的写法（GitHub 支持的绝对路径），其余相对当前文件。"""
    if target.startswith("/"):
        return ROOT / target.lstrip("/")
    return markdown.parent / target


def check(path: pathlib.Path) -> list[str]:
    broken: list[str] = []
    for target in targets(path.read_text()):
        if target.startswith(EXTERNAL):
            continue
        relative = target.strip("<>").split("#", 1)[0]
        if relative and not resolve(path, relative).exists():
            broken.append(f"{path}: {target}")
    return broken


def main() -> int:
    broken = [line for name in sys.argv[1:] for line in check(pathlib.Path(name))]
    if broken:
        sys.stderr.write("Markdown 相对链接指向不存在的路径：\n")
        sys.stderr.write("\n".join(broken) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
