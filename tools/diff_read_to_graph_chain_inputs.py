#!/usr/bin/env python3
"""Compare M6b read-to-graph chain_input TSV files."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
from pathlib import Path
import sys

from export_read_to_graph_input_boundary_pack import (
    CHAIN_HEADER,
    CHAIN_INPUT_SCHEMA,
    chain_input_text,
)
from replay_read_to_graph_input_boundary_pack import read_stable_overlap_tsv


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def canonical_chain_input(path: Path) -> str:
    rows = read_stable_overlap_tsv(path, CHAIN_INPUT_SCHEMA, CHAIN_HEADER)
    records = [row.to_input_boundary_record("chain_input") for row in rows]
    return chain_input_text(records)


def compare(left: Path, right: Path, include_diff: bool,
            max_diff_lines: int) -> dict:
    left_text = canonical_chain_input(left)
    right_text = canonical_chain_input(right)
    left_sha = sha256_text(left_text)
    right_sha = sha256_text(right_text)
    summary = {
        "schema": "cuflye-read-to-graph-chain-input-diff-v0",
        "status": "match" if left_sha == right_sha else "mismatch",
        "left": str(left.resolve()),
        "right": str(right.resolve()),
        "left_sha256": left_sha,
        "right_sha256": right_sha,
        "left_records": max(0, len(left_text.splitlines()) - 2),
        "right_records": max(0, len(right_text.splitlines()) - 2),
    }
    if include_diff and left_sha != right_sha:
        diff_lines = list(
            difflib.unified_diff(
                left_text.splitlines(keepends=True),
                right_text.splitlines(keepends=True),
                fromfile=str(left),
                tofile=str(right),
                n=3,
            )
        )
        summary["diff"] = "".join(diff_lines[:max_diff_lines])
        summary["diff_truncated"] = len(diff_lines) > max_diff_lines
    return summary


def print_report(summary: dict) -> None:
    print(f"Read-to-graph chain_input diff: {summary['status']}")
    print(f"  left        : {summary['left']}")
    print(f"  right       : {summary['right']}")
    print(f"  left records: {summary['left_records']}")
    print(f"  right records: {summary['right_records']}")
    print(f"  left sha    : {summary['left_sha256']}")
    print(f"  right sha   : {summary['right_sha256']}")
    if summary.get("diff"):
        print(summary["diff"], end="" if summary["diff"].endswith("\n") else "\n")
        if summary.get("diff_truncated"):
            print("... diff truncated ...")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", help="Left chain_input TSV")
    parser.add_argument("right", help="Right chain_input TSV")
    parser.add_argument("--json", action="store_true", help="Print JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary")
    parser.add_argument("--show-diff", action="store_true")
    parser.add_argument("--max-diff-lines", type=int, default=200)
    args = parser.parse_args(argv)

    try:
        summary = compare(
            Path(args.left),
            Path(args.right),
            include_diff=args.show_diff,
            max_diff_lines=args.max_diff_lines,
        )
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
