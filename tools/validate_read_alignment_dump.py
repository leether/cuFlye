#!/usr/bin/env python3
"""Validate cuFlye read-alignment-v1 TSV files."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path


INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1

Record = tuple[int, int, int, int, int, int, int, int, int, int, int, int, float]


class ReadAlignmentValidationError(ValueError):
    pass


def format_float(value: float) -> str:
    if value == 0:
        return "0"
    return format(value, ".9g")


def parse_int(value: str, name: str, line_no: int, path: Path) -> int:
    if value.startswith("+"):
        raise ReadAlignmentValidationError(
            f"{path}:{line_no}: {name} must not include an explicit plus sign"
        )
    try:
        return int(value, 10)
    except ValueError as exc:
        raise ReadAlignmentValidationError(
            f"{path}:{line_no}: {name} must be a decimal integer, got {value!r}"
        ) from exc


def parse_record(line: str, line_no: int, path: Path) -> Record:
    if not line.endswith("\n"):
        raise ReadAlignmentValidationError(f"{path}:{line_no}: line must end with LF")
    line = line[:-1]
    if not line:
        raise ReadAlignmentValidationError(f"{path}:{line_no}: blank records are not allowed")

    fields = line.split("\t")
    if len(fields) != 13:
        raise ReadAlignmentValidationError(
            f"{path}:{line_no}: expected 13 tab-separated fields, got {len(fields)}"
        )

    names = (
        "chain_id",
        "segment_id",
        "read_id",
        "read_begin",
        "read_end",
        "read_len",
        "edge_id",
        "edge_seq_id",
        "edge_begin",
        "edge_end",
        "edge_len",
        "score",
    )
    ints = [parse_int(value, name, line_no, path) for value, name in zip(fields[:12], names)]
    try:
        seq_divergence = float(fields[12])
    except ValueError as exc:
        raise ReadAlignmentValidationError(
            f"{path}:{line_no}: seq_divergence must be finite float, got {fields[12]!r}"
        ) from exc

    (
        chain_id,
        segment_id,
        read_id,
        read_begin,
        read_end,
        read_len,
        edge_id,
        edge_seq_id,
        edge_begin,
        edge_end,
        edge_len,
        score,
    ) = ints

    for name, value in (("read_id", read_id), ("edge_id", edge_id),
                        ("edge_seq_id", edge_seq_id), ("score", score)):
        if not INT64_MIN <= value <= INT64_MAX:
            raise ReadAlignmentValidationError(
                f"{path}:{line_no}: {name} is outside int64 range"
            )
    for name, value in (("chain_id", chain_id), ("segment_id", segment_id)):
        if value < 0:
            raise ReadAlignmentValidationError(f"{path}:{line_no}: {name} must be non-negative")
    if read_id == 0 or edge_id == 0 or edge_seq_id == 0:
        raise ReadAlignmentValidationError(f"{path}:{line_no}: ids must not be zero")
    if read_len <= 0 or edge_len <= 0:
        raise ReadAlignmentValidationError(f"{path}:{line_no}: lengths must be positive")
    for name, value in (
        ("read_begin", read_begin),
        ("read_end", read_end),
        ("edge_begin", edge_begin),
        ("edge_end", edge_end),
    ):
        if value < 0:
            raise ReadAlignmentValidationError(f"{path}:{line_no}: {name} must be non-negative")
    if read_begin > read_end or read_end >= read_len:
        raise ReadAlignmentValidationError(
            f"{path}:{line_no}: read range must satisfy 0 <= begin <= end < len"
        )
    if edge_begin > edge_end or edge_end >= edge_len:
        raise ReadAlignmentValidationError(
            f"{path}:{line_no}: edge range must satisfy 0 <= begin <= end < len"
        )
    if not math.isfinite(seq_divergence) or seq_divergence < 0:
        raise ReadAlignmentValidationError(
            f"{path}:{line_no}: seq_divergence must be finite and non-negative"
        )

    return (
        chain_id,
        segment_id,
        read_id,
        read_begin,
        read_end,
        read_len,
        edge_id,
        edge_seq_id,
        edge_begin,
        edge_end,
        edge_len,
        score,
        seq_divergence,
    )


def canonical_text(records: list[Record]) -> str:
    rows = []
    for record in sorted(records):
        *ints, seq_divergence = record
        rows.append("\t".join(str(value) for value in ints) + "\t" +
                    format_float(seq_divergence))
    return "\n".join(rows) + "\n"


def validate(path: Path, compute_canonical_sha256: bool = False) -> dict:
    records: list[Record] = []
    raw_sorted_by_canonical_key = True
    previous: Record | None = None
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            record = parse_record(line, line_no, path)
            if previous is not None and record < previous:
                raw_sorted_by_canonical_key = False
            previous = record
            records.append(record)
    if not records:
        raise ReadAlignmentValidationError(f"{path}: read alignment dump is empty")

    chain_ids = {record[0] for record in records}
    read_ids = {record[2] for record in records}
    edge_ids = {record[6] for record in records}
    summary = {
        "abi": "read-alignment-v1",
        "path": str(path.resolve()),
        "records": len(records),
        "chains": len(chain_ids),
        "reads": len(read_ids),
        "edges": len(edge_ids),
        "raw_sorted_by_canonical_key": raw_sorted_by_canonical_key,
    }
    if compute_canonical_sha256:
        summary["canonical_sha256"] = hashlib.sha256(
            canonical_text(records).encode("utf-8")
        ).hexdigest()
    return summary


def apply_expectations(summary: dict, args: argparse.Namespace) -> list[str]:
    errors: list[str] = []
    if args.expect_records is not None and summary["records"] != args.expect_records:
        errors.append(f"records expected {args.expect_records}, got {summary['records']}")
    if args.expect_chains is not None and summary["chains"] != args.expect_chains:
        errors.append(f"chains expected {args.expect_chains}, got {summary['chains']}")
    if args.expect_canonical_sha256:
        actual = summary.get("canonical_sha256")
        if actual is None:
            errors.append("--expect-canonical-sha256 requires --compute-canonical-sha256")
        elif actual != args.expect_canonical_sha256:
            errors.append(f"canonical_sha256 expected {args.expect_canonical_sha256}, got {actual}")
    if args.require_canonical_order and not summary["raw_sorted_by_canonical_key"]:
        errors.append("raw file is not sorted by canonical key")
    return errors


def print_report(summary: dict) -> None:
    print("Read alignment dump ABI: read-alignment-v1")
    print(f"  path           : {summary['path']}")
    print(f"  records        : {summary['records']}")
    print(f"  chains         : {summary['chains']}")
    print(f"  reads          : {summary['reads']}")
    print(f"  edges          : {summary['edges']}")
    if "canonical_sha256" in summary:
        print(f"  canonical sha  : {summary['canonical_sha256']}")
    print(f"  raw sorted     : {summary['raw_sorted_by_canonical_key']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("read_alignment_dump", help="Read alignment TSV path")
    parser.add_argument("--compute-canonical-sha256", action="store_true")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary to path")
    parser.add_argument("--expect-records", type=int)
    parser.add_argument("--expect-chains", type=int)
    parser.add_argument("--expect-canonical-sha256")
    parser.add_argument("--require-canonical-order", action="store_true")
    args = parser.parse_args(argv)

    try:
        summary = validate(
            Path(args.read_alignment_dump),
            compute_canonical_sha256=args.compute_canonical_sha256,
        )
    except ReadAlignmentValidationError as exc:
        print(f"ERROR: {exc}")
        return 1

    errors = apply_expectations(summary, args)
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
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
