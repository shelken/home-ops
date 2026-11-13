#!/usr/bin/env python3
"""检查 k8s/ 下 yaml-language-server 的 $schema 注释版本是否与 apiVersion 一致。

Renovate 升级 apiVersion 时不会同步改注释，编辑器会继续按旧版本 schema 校验。
只比较带 `_<版本>.json` 后缀的 schema；发现不一致时以非零退出。
"""

import re
import subprocess
import sys

SCHEMA = re.compile(r"yaml-language-server: \$schema=\S+_(v[0-9a-z]+)\.json")
API_VERSION = re.compile(r"^apiVersion:\s*(?:\S+/)?(v[0-9a-z]+)\s*$", re.MULTILINE)


def main() -> int:
    files = subprocess.run(
        ["git", "ls-files", "k8s/**/*.yaml", "k8s/**/*.yml"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()

    mismatches = []
    for path in files:
        text = open(path, encoding="utf-8").read()
        schema, api = SCHEMA.search(text), API_VERSION.search(text)
        if schema and api and schema.group(1) != api.group(1):
            mismatches.append(f"{path}：schema 为 {schema.group(1)}，apiVersion 为 {api.group(1)}")

    if mismatches:
        print("\n".join(mismatches))
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
