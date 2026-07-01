#!/usr/bin/env python3
"""Compare read-to-graph raw-overlap TSV files by M6g row key."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


RAW_SCHEMA = "# schema=cuflye-read-to-graph-raw-overlap-v0"
RAW_HEADER = (
    "query_id\tsource_order\traw_overlap_count\tchain_input_count\t"
    "read_id\tread_begin\tread_end\tread_len\tedge_seq_id\tedge_begin\t"
    "edge_end\tedge_len\tedge_id\tscore\tseq_divergence\t"
    "passes_chain_input_filter"
)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_raw_rows(path: Path) -> list[dict[str, Any]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) < 2:
        raise ValueError(f"{path}: missing schema/header")
    if lines[0] != RAW_SCHEMA:
        raise ValueError(f"{path}: unexpected schema")
    if lines[1] != RAW_HEADER:
        raise ValueError(f"{path}: unexpected header")
    rows = []
    for line in lines[2:]:
        fields = line.split("\t")
        if len(fields) != 16:
            raise ValueError(f"{path}: raw-overlap row must have 16 fields")
        rows.append(
            {
                "query_id": int(fields[0]),
                "read_id": int(fields[4]),
                "read_begin": int(fields[5]),
                "read_end": int(fields[6]),
                "read_len": int(fields[7]),
                "edge_seq_id": int(fields[8]),
                "edge_begin": int(fields[9]),
                "edge_end": int(fields[10]),
                "edge_len": int(fields[11]),
                "score": int(fields[13]),
            }
        )
    return rows


def row_key(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row["query_id"],
        row["read_id"],
        row["read_begin"],
        row["read_end"],
        row["read_len"],
        row["edge_seq_id"],
        row["edge_begin"],
        row["edge_end"],
        row["edge_len"],
        row["score"],
    )


def canonical_text(rows: list[dict[str, Any]]) -> str:
    lines = [
        "# schema=cuflye-read-to-graph-raw-overlap-row-key-v0",
        (
            "query_id\tread_id\tread_begin\tread_end\tread_len\t"
            "edge_seq_id\tedge_begin\tedge_end\tedge_len\tscore"
        ),
    ]
    for key in sorted(row_key(row) for row in rows):
        lines.append("\t".join(str(value) for value in key))
    return "\n".join(lines) + "\n"


def compare(left: Path, right: Path, include_diff: bool,
            max_diff_lines: int) -> dict[str, Any]:
    left_rows = read_raw_rows(left)
    right_rows = read_raw_rows(right)
    left_text = canonical_text(left_rows)
    right_text = canonical_text(right_rows)
    left_sha = sha256_text(left_text)
    right_sha = sha256_text(right_text)
    left_keys = [row_key(row) for row in left_rows]
    right_keys = [row_key(row) for row in right_rows]
    ordered_match = left_keys == right_keys
    right_set = set(right_keys)
    left_set = set(left_keys)
    missing = [list(key) for key in left_keys if key not in right_set]
    extra = [list(key) for key in right_keys if key not in left_set]
    summary: dict[str, Any] = {
        "schema": "cuflye-read-to-graph-raw-overlap-row-key-diff-v0",
        "status": "match" if left_sha == right_sha else "mismatch",
        "left": str(left.resolve()),
        "right": str(right.resolve()),
        "left_sha256": left_sha,
        "right_sha256": right_sha,
        "left_records": len(left_rows),
        "right_records": len(right_rows),
        "ordered_match": ordered_match,
        "matched_rows": len(set(left_keys) & set(right_keys)),
        "missing_rows": len(missing),
        "extra_rows": len(extra),
        "missing_examples": missing[:5],
        "extra_examples": extra[:5],
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


def print_report(summary: dict[str, Any]) -> None:
    print(f"Read-to-graph raw-overlap row-key diff: {summary['status']}")
    print(f"  left         : {summary['left']}")
    print(f"  right        : {summary['right']}")
    print(f"  left records : {summary['left_records']}")
    print(f"  right records: {summary['right_records']}")
    print(f"  ordered match: {summary['ordered_match']}")
    print(f"  matched rows : {summary['matched_rows']}")
    print(f"  missing rows : {summary['missing_rows']}")
    print(f"  extra rows   : {summary['extra_rows']}")
    print(f"  left sha     : {summary['left_sha256']}")
    print(f"  right sha    : {summary['right_sha256']}")
    if summary.get("diff"):
        print(summary["diff"], end="" if summary["diff"].endswith("\n") else "\n")
        if summary.get("diff_truncated"):
            print("... diff truncated ...")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", help="Left raw-overlap TSV")
    parser.add_argument("right", help="Right raw-overlap TSV")
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
