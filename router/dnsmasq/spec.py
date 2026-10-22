"""home-ops 独占的路由器 dnsmasq 配置目录。"""

from __future__ import annotations

import os
import pathlib
from string import Template

from declare import File, Spec

HERE = pathlib.Path(__file__).resolve().parent


def spec() -> Spec:
    conf_dir = os.environ["DNS_MANAGED_CONF_DIR"]
    values = {k: os.environ[k] for k in ("MAIN_DOMAIN", "INTERNAL_DOMAIN", "DNS_GATEWAY")}
    templates = sorted((HERE / "conf.d").glob("*.conf.tpl"))
    if not templates:
        raise SystemExit(f"{HERE / 'conf.d'} 下没有可下发的配置")
    files = tuple(
        File(f"{conf_dir}/{t.name.removesuffix('.tpl')}", Template(t.read_text()).substitute(values).encode())
        for t in templates
    )
    probe = next(
        line.split("/")[1]
        for line in (HERE / "conf.d/30-bootstrap.conf.tpl").read_text().splitlines()
        if line.startswith("address=/")
    )
    return Spec(
        files=files,
        validate=f"dnsmasq --test --conf-file=/dev/null --conf-dir={{stage}}{conf_dir},*.conf",
        reload="/etc/init.d/dnsmasq restart",
        verify=f"pidof dnsmasq >/dev/null && nslookup {probe} 127.0.0.1",
        owned_dir=conf_dir,
    )
