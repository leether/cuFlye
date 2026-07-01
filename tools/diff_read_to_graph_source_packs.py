#!/usr/bin/env python3
"""Compare M6d read-to-graph minimizer source packs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from validate_read_to_graph_source_pack import validate_pack


def compare(left: Path, right: Path) -> dict:
    left_summary = validate_pack(left)
    right_summary = validate_pack(right)
    return {
        "schema": "cuflye-read-to-graph-minimizer-source-pack-diff-v0",
        "status": (
            "match"
            if left_summary["canonical_sha256"] == right_summary["canonical_sha256"]
            else "mismatch"
        ),
        "left": str(left.resolve()),
        "right": str(right.resolve()),
        "left_query_count": left_summary["query_count"],
        "right_query_count": right_summary["query_count"],
        "left_query_ids": left_summary["query_ids"],
        "right_query_ids": right_summary["query_ids"],
        "left_sha256": left_summary["canonical_sha256"],
        "right_sha256": right_summary["canonical_sha256"],
        "left_total_counts": left_summary["total_counts"],
        "right_total_counts": right_summary["total_counts"],
    }


def print_report(summary: dict) -> None:
    print(f"Read-to-graph minimizer source pack diff: {summary['status']}")
    print(f"  left : {summary['left']}")
    print(f"  right: {summary['right']}")
    print(f"  left sha : {summary['left_sha256']}")
    print(f"  right sha: {summary['right_sha256']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", help="Left source-pack root")
    parser.add_argument("right", help="Right source-pack root")
    parser.add_argument("--json", action="store_true", help="Print JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary")
    args = parser.parse_args(argv)

    try:
        summary = compare(Path(args.left), Path(args.right))
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json_output:
        output_path = Path(args.json_output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print_report(summary)
    return 0 if summary["status"] == "match" else 1


if __name__ == "__main__":
    sys.exit(main())
