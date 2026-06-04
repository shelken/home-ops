#!/usr/bin/env python3
"""Summarize Gatus in-memory endpoint status results.

Gatus without storage only keeps results since the current process started. This
script makes that runtime window explicit, then highlights current failures,
endpoints that failed at least once, and optional endpoint timelines.
"""

import argparse
import json
import subprocess
import sys
from typing import Any

DEFAULT_NAMESPACE = "observability"
DEFAULT_SERVICE = "gatus"
DEFAULT_PORT = "80"


def run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed: {' '.join(cmd)}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    return proc.stdout


def load_json(args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.raw_file:
        with open(args.raw_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        service_path = (
            f"/api/v1/namespaces/{args.namespace}/services/"
            f"http:{args.service}:{args.port}/proxy/api/v1/endpoints/statuses"
        )
        cmd = ["kubectl"]
        if args.context:
            cmd.extend(["--context", args.context])
        cmd.extend(["-n", args.namespace, "get", "--raw", service_path])
        data = json.loads(run(cmd))

    if not isinstance(data, list):
        raise ValueError("Gatus statuses response must be a JSON array")
    return data


def endpoint_matches(endpoint: dict[str, Any], args: argparse.Namespace) -> bool:
    if args.key and endpoint.get("key") != args.key:
        return False
    if args.group and endpoint.get("group") != args.group:
        return False
    if args.name and endpoint.get("name") != args.name:
        return False
    return True


def results(endpoint: dict[str, Any]) -> list[dict[str, Any]]:
    value = endpoint.get("results", [])
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def last_result(endpoint: dict[str, Any]) -> dict[str, Any] | None:
    items = results(endpoint)
    return items[-1] if items else None


def is_success(result: dict[str, Any] | None) -> bool:
    return bool(result and result.get("success") is True)


def failed_conditions(result: dict[str, Any]) -> list[str]:
    conditions = result.get("conditionResults") or []
    if not isinstance(conditions, list):
        return []
    failed: list[str] = []
    for condition in conditions:
        if not isinstance(condition, dict):
            continue
        if condition.get("success") is False:
            failed.append(str(condition.get("condition", "<unknown-condition>")))
    return failed


def failure_count(endpoint: dict[str, Any]) -> int:
    return sum(1 for item in results(endpoint) if item.get("success") is False)


def first_timestamp(endpoint: dict[str, Any]) -> str | None:
    items = results(endpoint)
    if not items:
        return None
    value = items[0].get("timestamp")
    return str(value) if value else None


def last_timestamp(endpoint: dict[str, Any]) -> str | None:
    item = last_result(endpoint)
    if not item:
        return None
    value = item.get("timestamp")
    return str(value) if value else None


def duration_text(value: Any) -> str:
    if value is None:
        return "-"
    try:
        ns = float(value)
    except (TypeError, ValueError):
        return str(value)
    ms = ns / 1_000_000
    if ms < 10:
        return f"{ms:.1f}ms"
    if ms < 1_000:
        return f"{ms:.0f}ms"
    return f"{ms / 1_000:.2f}s"


def endpoint_label(endpoint: dict[str, Any]) -> str:
    group = endpoint.get("group", "<no-group>")
    name = endpoint.get("name", "<no-name>")
    key = endpoint.get("key", "<no-key>")
    return f"{group}/{name} key={key}"


def summarize(endpoints: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    filtered = [endpoint for endpoint in endpoints if endpoint_matches(endpoint, args)]
    if not filtered:
        raise ValueError("no Gatus endpoints matched filters")

    timestamps_start = [ts for endpoint in filtered if (ts := first_timestamp(endpoint))]
    timestamps_end = [ts for endpoint in filtered if (ts := last_timestamp(endpoint))]
    current_failed = [endpoint for endpoint in filtered if not is_success(last_result(endpoint))]
    ever_failed = [endpoint for endpoint in filtered if failure_count(endpoint) > 0]
    top_failures = sorted(
        ever_failed,
        key=lambda endpoint: (-failure_count(endpoint), endpoint.get("group", ""), endpoint.get("name", "")),
    )[: args.top]

    return {
        "total_endpoints": len(endpoints),
        "matched_endpoints": len(filtered),
        "window_start": min(timestamps_start) if timestamps_start else None,
        "window_end": max(timestamps_end) if timestamps_end else None,
        "current_failed": current_failed,
        "ever_failed": ever_failed,
        "top_failures": top_failures,
        "filtered": filtered,
    }


def result_for_json(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "timestamp": result.get("timestamp"),
        "success": result.get("success"),
        "status": result.get("status"),
        "duration_ns": result.get("duration"),
        "failed_conditions": failed_conditions(result),
        "error": result.get("error"),
    }


def endpoint_for_json(endpoint: dict[str, Any]) -> dict[str, Any]:
    last = last_result(endpoint)
    return {
        "group": endpoint.get("group"),
        "name": endpoint.get("name"),
        "key": endpoint.get("key"),
        "failure_count": failure_count(endpoint),
        "last_success": is_success(last),
        "last_timestamp": last.get("timestamp") if last else None,
    }


def print_json(summary: dict[str, Any], args: argparse.Namespace) -> None:
    timeline = []
    for endpoint in summary["filtered"]:
        items = results(endpoint)
        if not args.all_results:
            items = [item for item in items if item.get("success") is False]
        timeline.append(
            {
                **endpoint_for_json(endpoint),
                "results": [result_for_json(item) for item in items],
            }
        )

    payload = {
        "source": {
            "namespace": args.namespace,
            "service": args.service,
            "port": args.port,
            "raw_file": args.raw_file,
        },
        "filters": {"group": args.group, "name": args.name, "key": args.key},
        "summary": {
            "total_endpoints": summary["total_endpoints"],
            "matched_endpoints": summary["matched_endpoints"],
            "window_start": summary["window_start"],
            "window_end": summary["window_end"],
            "current_failed": len(summary["current_failed"]),
            "ever_failed": len(summary["ever_failed"]),
        },
        "current_failed": [endpoint_for_json(endpoint) for endpoint in summary["current_failed"]],
        "top_failures": [endpoint_for_json(endpoint) for endpoint in summary["top_failures"]],
        "timeline": timeline,
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def print_text(summary: dict[str, Any], args: argparse.Namespace) -> None:
    print("Gatus runtime window:")
    print(f"  endpoints: {summary['total_endpoints']}")
    if summary["matched_endpoints"] != summary["total_endpoints"]:
        print(f"  matched endpoints: {summary['matched_endpoints']}")
    print(f"  window: {summary['window_start']} -> {summary['window_end']}")
    print(f"  current failed: {len(summary['current_failed'])}")
    print(f"  ever failed: {len(summary['ever_failed'])}")

    print("\nCurrent failed:")
    if not summary["current_failed"]:
        print("  none")
    for endpoint in sorted(summary["current_failed"], key=lambda item: endpoint_label(item)):
        last = last_result(endpoint) or {}
        failed = "; ".join(failed_conditions(last)) or "-"
        print(
            f"  {endpoint_label(endpoint)} status={last.get('status', '-')} "
            f"duration={duration_text(last.get('duration'))} ts={last.get('timestamp', '-')} "
            f"failed={failed}"
        )

    print("\nTop historical failures:")
    if not summary["top_failures"]:
        print("  none")
    for endpoint in summary["top_failures"]:
        last = last_result(endpoint)
        print(
            f"  {failure_count(endpoint):>4}  last_success={str(is_success(last)).lower():<5}  "
            f"{endpoint_label(endpoint)} last={last_timestamp(endpoint)}"
        )

    if args.key or args.group or args.name:
        print("\nTimeline:")
        for endpoint in sorted(summary["filtered"], key=lambda item: endpoint_label(item)):
            print(f"  {endpoint_label(endpoint)}")
            items = results(endpoint)
            if not args.all_results:
                items = [item for item in items if item.get("success") is False]
            if not items:
                print("    no matching results in visible window")
                continue
            for item in items:
                failed = "; ".join(failed_conditions(item)) or "-"
                error = item.get("error") or "-"
                print(
                    f"    {item.get('timestamp', '-')} success={str(item.get('success')).lower()} "
                    f"status={item.get('status', '-')} duration={duration_text(item.get('duration'))} "
                    f"failed={failed} error={error}"
                )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize Gatus runtime endpoint status data from its in-memory API."
    )
    parser.add_argument("--namespace", default=DEFAULT_NAMESPACE, help="Gatus namespace")
    parser.add_argument("--service", default=DEFAULT_SERVICE, help="Gatus service name")
    parser.add_argument("--port", default=DEFAULT_PORT, help="Gatus service port")
    parser.add_argument("--context", help="kubectl context")
    parser.add_argument("--raw-file", help="Read statuses JSON from a file instead of kubectl")
    parser.add_argument("--group", help="Exact Gatus endpoint group filter")
    parser.add_argument("--name", help="Exact Gatus endpoint name filter")
    parser.add_argument("--key", help="Exact Gatus endpoint key filter")
    parser.add_argument("--top", type=int, default=20, help="Number of historical failures to show")
    parser.add_argument("--all-results", action="store_true", help="Show all timeline results, not only failures")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    args = parser.parse_args(argv)
    if args.top < 1:
        raise ValueError("--top must be >= 1")
    return args


def main(argv: list[str]) -> int:
    try:
        args = parse_args(argv)
        endpoints = load_json(args)
        summary = summarize(endpoints, args)
        if args.json:
            print_json(summary, args)
        else:
            print_text(summary, args)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
