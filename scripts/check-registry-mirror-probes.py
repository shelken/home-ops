#!/usr/bin/env python3
"""校验 registries.yaml 的外部镜像端点与 Gatus 探测清单一一对应。"""

from __future__ import annotations

import pathlib
import re
import sys
import urllib.request
from fnmatch import fnmatchcase

ROOT = pathlib.Path(__file__).resolve().parent.parent
# 节点的 registries.yaml 由 nix-config 声明；读 main 分支上的版本
REGISTRIES_NAME = "nix-config modules/features/homelab/k3s-node/registries.yaml"
REGISTRIES_URL = "https://raw.githubusercontent.com/shelken/nix-config/main/modules/features/homelab/k3s-node/registries.yaml"
PROBES = ROOT / "k8s/infra/common/observability/gatus/app/resources/outside/registry-mirror.yaml"

ENDPOINT = re.compile(r'^\s*-\s*"https://([^/"]+)', re.MULTILINE)
QUERY = re.compile(r"^\s*query-name:\s*(\S+)", re.MULTILINE)

# *.int 只在内网可解析，由 sakamoto 分组的 TCP 探测覆盖
registries_text = urllib.request.urlopen(REGISTRIES_URL, timeout=30).read().decode()
endpoints = {h for h in ENDPOINT.findall(registries_text) if ".int." not in h}
patterns = {q.replace("${MAIN_DOMAIN}", "*") for q in QUERY.findall(PROBES.read_text())}

unprobed = sorted(h for h in endpoints if not any(fnmatchcase(h, p) for p in patterns))
stale = sorted(p for p in patterns if not any(fnmatchcase(h, p) for h in endpoints))

for host in unprobed:
    print(f"{REGISTRIES_NAME}: {host} 没有对应的 Gatus 探测")
for pattern in stale:
    print(f"{PROBES.relative_to(ROOT)}: {pattern} 已不在 registries.yaml 中")
sys.exit(1 if unprobed or stale else 0)
