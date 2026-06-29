#!/usr/bin/env python3
"""Compare cuFlye candidate dump TSV files."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
from pathlib import Path


def parse_line(line: str, line_no: int, path: Path) -> tuple[int, int, int, int, int, str]:
    parts = line.rstrip("\n").split("\t")
    if len(parts) != 6:
        raise ValueError(f"{path}:{line_no}: expected 6 tab-separated fields, got {len(parts)}")
    query_id, query_pos, kmer, target_id, target_pos, strand = parts
    return (
        int(query_id),
        int(query_pos),
        int(kmer),
        int(target_id),
        int(target_pos),
        strand,
    )


def canonical_records(path: Path) -> list[tuple[int, int, int, int, int, str]]:
    records = []
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            if not line.strip():
                continue
            records.append(parse_line(line, line_no, path))
    records.sort()
    return records


def canonical_text(records: list[tuple[int, int, int, int, int, str]]) -> str:
    return "".join(
        f"{query_id}\t{query_pos}\t{kmer}\t{target_id}\t{target_pos}\t{strand}\n"
        for query_id, query_pos, kmer, target_id, target_pos, strand in records
    )


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def compare(left: Path, right: Path, include_diff: bool = False, max_diff_lines: int = 200) -> dict:
    left_records = canonical_records(left)
    right_records = canonical_records(right)
    left_text = canonical_text(left_records)
    right_text = canonical_text(right_records)
    left_hash = sha256(left_text)
    right_hash = sha256(right_text)

    summary = {
        "status": "match" if left_hash == right_hash else "mismatch",
        "left": str(left.resolve()),
        "right": str(right.resolve()),
        "left_records": len(left_records),
        "right_records": len(right_records),
        "left_sha256": left_hash,
        "right_sha256": right_hash,
    }

    if include_diff and left_hash != right_hash:
        diff_lines = list(difflib.unified_diff(
            left_text.splitlines(keepends=True),
            right_text.splitlines(keepends=True),
            fromfile=str(left),
            tofile=str(right),
            n=3,
        ))
        truncated = len(diff_lines) > max_diff_lines
        summary["diff"] = "".join(diff_lines[:max_diff_lines])
        summary["diff_truncated"] = truncated

    return summary


def print_report(summary: dict) -> None:
    print(f"Candidate dump diff: {summary['status']}")
    print(f"  left : {summary['left']}")
    print(f"  right: {summary['right']}")
    print(f"  left records : {summary['left_records']}")
    print(f"  right records: {summary['right_records']}")
    print(f"  left sha256  : {summary['left_sha256']}")
    print(f"  right sha256 : {summary['right_sha256']}")
    if summary.get("diff"):
        print(summary["diff"], end="" if summary["diff"].endswith("\n") else "\n")
        if summary.get("diff_truncated"):
            print("... diff truncated ...")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", help="Left candidate TSV")
    parser.add_argument("right", help="Right candidate TSV")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary to this path")
    parser.add_argument("--show-diff", action="store_true", help="Show bounded unified diff on mismatch")
    parser.add_argument("--max-diff-lines", type=int, default=200)
    args = parser.parse_args(argv)

    summary = compare(
        Path(args.left),
        Path(args.right),
        include_diff=args.show_diff,
        max_diff_lines=args.max_diff_lines,
    )

    if args.json_output:
        Path(args.json_output).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print_report(summary)

    return 0 if summary["status"] == "match" else 1


if __name__ == "__main__":
    raise SystemExit(main())
