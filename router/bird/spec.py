"""主路由的 BIRD 配置，home-ops 整体管理 /etc/bird.conf。"""

from __future__ import annotations

import pathlib

from declare import File, Spec

HERE = pathlib.Path(__file__).resolve().parent


def spec() -> Spec:
    return Spec(
        files=(File("/etc/bird.conf", (HERE / "mine.conf").read_bytes()),),
        validate="bird -p -c {stage}/etc/bird.conf",
        # 软重配，不中断既有 BGP 会话
        reload="birdc configure",
        verify="birdc show protocols",
    )
