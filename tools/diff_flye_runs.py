#!/usr/bin/env python3
"""Compare canonical Flye artifacts from two run directories."""

from __future__ import annotations

import argparse
import difflib
import json
from pathlib import Path
import sys

import canonicalize_flye_artifacts as canon


def artifact_text(run_dir: Path, rel_path: str, sort_fasta_records: bool) -> str | None:
    path = run_dir / rel_path
    if not path.exists():
        return None
    return canon.canonicalize(path, sort_fasta_records=sort_fasta_records)


def compare_runs(
    left: Path,
    right: Path,
    artifacts: list[str],
    sort_fasta_records: bool = False,
    include_diff: bool = False,
) -> dict:
    results = []
    for rel_path in artifacts:
        left_text = artifact_text(left, rel_path, sort_fasta_records)
        right_text = artifact_text(right, rel_path, sort_fasta_records)
        item = {
            "path": rel_path,
            "left_present": left_text is not None,
            "right_present": right_text is not None,
        }
        if left_text is None or right_text is None:
            item["status"] = "missing"
        else:
            left_sha = canon.sha256_text(left_text)
            right_sha = canon.sha256_text(right_text)
            item["left_sha256"] = left_sha
            item["right_sha256"] = right_sha
            if left_sha == right_sha:
                item["status"] = "match"
            else:
                item["status"] = "mismatch"
                if include_diff:
                    item["diff"] = "".join(difflib.unified_diff(
                        left_text.splitlines(keepends=True),
                        right_text.splitlines(keepends=True),
                        fromfile=f"{left}/{rel_path}",
                        tofile=f"{right}/{rel_path}",
                        n=3,
                    ))
        results.append(item)

    status = "match" if all(item["status"] == "match" for item in results if item["left_present"] or item["right_present"]) else "mismatch"
    if not any(item["left_present"] or item["right_present"] for item in results):
        status = "missing"
    return {
        "status": status,
        "left": str(left.resolve()),
        "right": str(right.resolve()),
        "sort_fasta_records": sort_fasta_records,
        "artifacts": results,
    }


def print_report(summary: dict) -> None:
    print(f"Flye run diff: {summary['status']}")
    print(f"  left : {summary['left']}")
    print(f"  right: {summary['right']}")
    for item in summary["artifacts"]:
        state = item["status"]
        print(f"  {state:8} {item['path']}")
        if state == "mismatch":
            print(f"           left  {item['left_sha256']}")
            print(f"           right {item['right_sha256']}")
        if state == "missing":
            print(f"           present left={item['left_present']} right={item['right_present']}")
        if item.get("diff"):
            print(item["diff"], end="" if item["diff"].endswith("\n") else "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", help="Left Flye run directory")
    parser.add_argument("right", help="Right Flye run directory")
    parser.add_argument("--artifact", action="append", dest="artifacts", help="Relative artifact path to compare; may be repeated")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary to this path")
    parser.add_argument("--show-diff", action="store_true", help="Include unified text diff for mismatched artifacts")
    parser.add_argument("--sort-fasta-records", action="store_true", help="Sort FASTA records by header before comparing")
    args = parser.parse_args(argv)

    artifacts = args.artifacts or canon.DEFAULT_ARTIFACTS
    summary = compare_runs(
        Path(args.left),
        Path(args.right),
        artifacts,
        sort_fasta_records=args.sort_fasta_records,
        include_diff=args.show_diff,
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
