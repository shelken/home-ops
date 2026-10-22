"""旁路由 dae：上游 release 二进制、home-ops 的 init 脚本、SOPS 加密的配置，并以 dae 取代 daed。"""

from __future__ import annotations

import hashlib
import io
import os
import pathlib
import re
import subprocess
import urllib.request
import zipfile

from declare import File, Service, Spec

HERE = pathlib.Path(__file__).resolve().parent
ASSET = "dae-linux-arm64"
RUNNING = "/etc/init.d/dae running"


def version() -> str:
    return re.search(r"^version:\s*(\S+)", (HERE / "version.yaml").read_text(), re.MULTILINE)[1]


def binary(tag: str) -> bytes:
    cache = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache")) / "home-ops" / f"{ASSET}-{tag}.zip"
    if not cache.exists():
        base = f"https://github.com/daeuniverse/dae/releases/download/{tag}/{ASSET}.zip"
        data = urllib.request.urlopen(base).read()
        digest = urllib.request.urlopen(f"{base}.dgst").read().decode()
        expected = next(line.split()[0] for line in digest.splitlines() if line.endswith(" sha256"))
        if hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit(f"{ASSET}.zip {tag} 的 sha256 与 .dgst 不符")
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_bytes(data)
    return zipfile.ZipFile(io.BytesIO(cache.read_bytes())).read(ASSET)


def config() -> bytes:
    return subprocess.run(
        ["sops", "-d", str(HERE / "config.sops.dae")],
        check=True,
        capture_output=True,
    ).stdout


def spec() -> Spec:
    restart = f"if {RUNNING}; then /etc/init.d/dae restart; fi"
    return Spec(
        files=(
            File("/usr/bin/dae", binary(version()), 0o755, reload=restart),
            File("/etc/init.d/dae", (HERE / "dae.init").read_bytes(), 0o755, reload=restart),
            File("/etc/dae/config.dae", config(), 0o600, sensitive=True),
        ),
        validate="{stage}/usr/bin/dae validate -c {stage}/etc/dae/config.dae",
        reload=f"if {RUNNING}; then /etc/init.d/dae hot_reload; fi",
        verify=f"{RUNNING} && /usr/bin/dae --version | head -n 1",
        services=(Service("daed", False), Service("dae", True)),
    )
