#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import List

OBS_NS = "observability"
VL_SERVICE = "victoria-logs-server"
ALERT_LABEL = "app.kubernetes.io/name=alertmanager"


@dataclass(frozen=True)
class VLSection:
    name: str
    namespace: str
    pod_regex: str
    container: str | None = None


@dataclass(frozen=True)
class KubectlSection:
    name: str
    namespace: str
    container: str
    pod: str | None = None
    selector: str | None = None


def run(cmd: List[str], *, check: bool = True) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"command failed: {' '.join(cmd)}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    return proc.stdout


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def parse_utc(value: str) -> dt.datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = dt.datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise ValueError(f"time must include timezone: {value}")
    return parsed.astimezone(dt.timezone.utc)


def resolve_window(args: argparse.Namespace) -> tuple[dt.datetime, dt.datetime]:
    if args.start and args.end:
        start = parse_utc(args.start)
        end = parse_utc(args.end)
    elif args.hours:
        end = utc_now()
        start = end - dt.timedelta(hours=args.hours)
    else:
        raise ValueError("must provide --hours or both --start and --end")
    if start >= end:
        raise ValueError("start must be earlier than end")
    return start, end


def resolve_vl_endpoint(cli_value: str | None) -> str:
    if cli_value:
        return cli_value

    configured = os.getenv("VL_ENDPOINT")
    if configured:
        return configured

    raw = run(["kubectl", "-n", OBS_NS, "get", "svc", VL_SERVICE, "-o", "json"])
    data = json.loads(raw)
    ingress = data.get("status", {}).get("loadBalancer", {}).get("ingress", [])
    if ingress:
        item = ingress[0]
        if item.get("ip"):
            return f"{item['ip']}:9428"
        if item.get("hostname"):
            return f"{item['hostname']}:9428"

    cluster_ip = data.get("spec", {}).get("clusterIP")
    if cluster_ip and cluster_ip != "None":
        return f"{cluster_ip}:9428"

    raise RuntimeError("cannot resolve Victoria Logs endpoint; set --vl-endpoint or VL_ENDPOINT")


def fetch_vl(endpoint: str, query: str, limit: int) -> list[dict]:
    url = f"http://{endpoint}/select/logsql/query"
    params = urllib.parse.urlencode({"query": query, "limit": str(limit)})
    with urllib.request.urlopen(f"{url}?{params}") as resp:
        payload = resp.read().decode("utf-8", errors="replace")
    rows = []
    for line in payload.splitlines():
        line = line.strip()
        if not line:
            continue
        rows.append(json.loads(line))
    return rows


def vl_query(section: VLSection, start: dt.datetime, end: dt.datetime) -> str:
    parts = [
        f'k_namespace_name="{section.namespace}"',
        f'k_pod_name=~"{section.pod_regex}"',
    ]
    if section.container:
        parts.append(f'k_container_name="{section.container}"')
    stream = ",".join(parts)
    return (
        f'_stream:{{{stream}}} '
        f"_time:[{start.strftime('%Y-%m-%dT%H:%M:%SZ')},{end.strftime('%Y-%m-%dT%H:%M:%SZ')}] "
        "| fields _time,_msg,k_pod_name,k_container_name"
    )


def parse_spec(spec: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        if "=" not in item:
            raise ValueError(f"invalid section spec item: {item}")
        key, value = item.split("=", 1)
        result[key.strip()] = value.strip()
    return result


def build_vl_section(spec: dict[str, str]) -> VLSection:
    required = ["name", "namespace", "pod"]
    for key in required:
        if key not in spec or not spec[key]:
            raise ValueError(f"vl section missing {key}: {spec}")
    return VLSection(
        name=spec["name"],
        namespace=spec["namespace"],
        pod_regex=spec["pod"],
        container=spec.get("container"),
    )


def build_kubectl_section(spec: dict[str, str]) -> KubectlSection:
    required = ["name", "namespace", "container"]
    for key in required:
        if key not in spec or not spec[key]:
            raise ValueError(f"kubectl section missing {key}: {spec}")
    pod = spec.get("pod")
    selector = spec.get("selector")
    if not pod and not selector:
        raise ValueError(f"kubectl section requires pod or selector: {spec}")
    return KubectlSection(
        name=spec["name"],
        namespace=spec["namespace"],
        container=spec["container"],
        pod=pod,
        selector=selector,
    )


def resolve_pod_from_selector(namespace: str, selector: str) -> str:
    raw = run(["kubectl", "-n", namespace, "get", "pods", "-l", selector, "-o", "json"])
    items = json.loads(raw).get("items", [])
    if not items:
        raise RuntimeError(f"cannot resolve pod for selector {selector} in namespace {namespace}")
    items.sort(key=lambda item: item["metadata"]["name"])
    return items[0]["metadata"]["name"]


def collect_kubectl_lines(section: KubectlSection, start: dt.datetime) -> list[str]:
    pod = section.pod or resolve_pod_from_selector(section.namespace, section.selector or "")
    output = run(
        [
            "kubectl",
            "-n",
            section.namespace,
            "logs",
            pod,
            "-c",
            section.container,
            f"--since-time={start.strftime('%Y-%m-%dT%H:%M:%SZ')}",
        ]
    )
    return output.splitlines()


def print_vl_section(section: VLSection, rows: list[dict]) -> None:
    print(f"\n=== victoria-logs:{section.name} ===")
    if not rows:
        print("(no lines)")
        return
    for row in rows:
        when = row.get("_time", "")
        pod = row.get("k_pod_name", "")
        container = row.get("k_container_name", "")
        msg = row.get("_msg", "")
        print(f"{when} [{pod}/{container}] {msg}")


def print_kubectl_section(section: KubectlSection, lines: list[str]) -> None:
    print(f"\n=== kubectl-logs:{section.name} ===")
    if not lines:
        print("(no lines)")
        return
    for line in lines:
        print(line)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="按时间窗汇总 Victoria Logs 与 kubectl logs")
    parser.add_argument("--hours", type=float, default=6, help="回看最近多少小时")
    parser.add_argument("--start", help="UTC 开始时间，例如 2026-05-24T02:50:00Z")
    parser.add_argument("--end", help="UTC 结束时间，例如 2026-05-24T03:10:00Z")
    parser.add_argument("--limit", type=int, default=200, help="Victoria Logs 每段最多返回多少行")
    parser.add_argument("--vl-endpoint", help="Victoria Logs 地址，例如 192.168.69.66:9428")
    parser.add_argument(
        "--vl-section",
        action="append",
        default=[],
        help="Victoria Logs 段，例如 name=gatus,namespace=observability,pod=gatus.*",
    )
    parser.add_argument(
        "--kubectl-section",
        action="append",
        default=[],
        help="kubectl logs 段，例如 name=alertmanager,namespace=observability,selector=app.kubernetes.io/name=alertmanager,container=alertmanager",
    )
    parser.add_argument("--skip-kubectl", action="store_true", help="只看 Victoria Logs")
    return parser


def build_sections(args: argparse.Namespace) -> tuple[list[VLSection], list[KubectlSection]]:
    vl_sections = [build_vl_section(parse_spec(item)) for item in args.vl_section]
    kubectl_sections = [build_kubectl_section(parse_spec(item)) for item in args.kubectl_section]

    if not vl_sections and not kubectl_sections:
        raise ValueError("no sections configured; use --vl-section or --kubectl-section")

    if args.skip_kubectl:
        kubectl_sections = []

    return vl_sections, kubectl_sections


def main() -> int:
    args = build_parser().parse_args()
    start, end = resolve_window(args)
    vl_sections, kubectl_sections = build_sections(args)
    vl_endpoint = resolve_vl_endpoint(args.vl_endpoint)

    print(f"window_start={start.strftime('%Y-%m-%dT%H:%M:%SZ')}")
    print(f"window_end={end.strftime('%Y-%m-%dT%H:%M:%SZ')}")
    print(f"vl_endpoint={vl_endpoint}")
    print(f"vl_sections={len(vl_sections)}")
    print(f"kubectl_sections={len(kubectl_sections)}")

    for section in vl_sections:
        rows = fetch_vl(vl_endpoint, vl_query(section, start, end), args.limit)
        print_vl_section(section, rows)

    for section in kubectl_sections:
        lines = collect_kubectl_lines(section, start)
        print_kubectl_section(section, lines)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
