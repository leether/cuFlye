#!/usr/bin/env python3
"""Validate cuFlye overlap-range-v1 TSV files."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path


INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1

Record = tuple[int, int, int, int, int, int, int, int, int, float]


class OverlapValidationError(ValueError):
    pass


def format_float(value: float) -> str:
    if value == 0:
        return "0"
    return format(value, ".9g")


def parse_int(value: str, name: str, line_no: int, path: Path) -> int:
    if value.startswith("+"):
        raise OverlapValidationError(
            f"{path}:{line_no}: {name} must not include an explicit plus sign"
        )
    try:
        parsed = int(value, 10)
    except ValueError as exc:
        raise OverlapValidationError(
            f"{path}:{line_no}: {name} must be a decimal integer, got {value!r}"
        ) from exc
    return parsed


def parse_record(line: str, line_no: int, path: Path) -> Record:
    if not line.endswith("\n"):
        raise OverlapValidationError(f"{path}:{line_no}: line must end with LF")
    line = line[:-1]
    if not line:
        raise OverlapValidationError(f"{path}:{line_no}: blank records are not allowed")

    fields = line.split("\t")
    if len(fields) != 10:
        raise OverlapValidationError(
            f"{path}:{line_no}: expected 10 tab-separated fields, got {len(fields)}"
        )

    names = (
        "cur_id",
        "cur_begin",
        "cur_end",
        "cur_len",
        "ext_id",
        "ext_begin",
        "ext_end",
        "ext_len",
        "score",
    )
    ints = [parse_int(value, name, line_no, path) for value, name in zip(fields[:9], names)]
    try:
        seq_divergence = float(fields[9])
    except ValueError as exc:
        raise OverlapValidationError(
            f"{path}:{line_no}: seq_divergence must be finite float, got {fields[9]!r}"
        ) from exc

    (
        cur_id,
        cur_begin,
        cur_end,
        cur_len,
        ext_id,
        ext_begin,
        ext_end,
        ext_len,
        score,
    ) = ints

    for name, value in (("cur_id", cur_id), ("ext_id", ext_id), ("score", score)):
        if not INT64_MIN <= value <= INT64_MAX:
            raise OverlapValidationError(f"{path}:{line_no}: {name} is outside int64 range")
    if cur_id == 0 or ext_id == 0:
        raise OverlapValidationError(f"{path}:{line_no}: ids must not be zero")
    if cur_len <= 0 or ext_len <= 0:
        raise OverlapValidationError(f"{path}:{line_no}: lengths must be positive")
    for name, value in (
        ("cur_begin", cur_begin),
        ("cur_end", cur_end),
        ("ext_begin", ext_begin),
        ("ext_end", ext_end),
    ):
        if value < 0:
            raise OverlapValidationError(f"{path}:{line_no}: {name} must be non-negative")
    if cur_begin > cur_end or cur_end >= cur_len:
        raise OverlapValidationError(
            f"{path}:{line_no}: current range must satisfy 0 <= begin <= end < len"
        )
    if ext_begin > ext_end or ext_end >= ext_len:
        raise OverlapValidationError(
            f"{path}:{line_no}: extension range must satisfy 0 <= begin <= end < len"
        )
    if not math.isfinite(seq_divergence) or seq_divergence < 0:
        raise OverlapValidationError(
            f"{path}:{line_no}: seq_divergence must be finite and non-negative"
        )

    return (
        cur_id,
        cur_begin,
        cur_end,
        cur_len,
        ext_id,
        ext_begin,
        ext_end,
        ext_len,
        score,
        seq_divergence,
    )


def canonical_text(records: list[Record]) -> str:
    return "".join(
        "\t".join(
            [
                str(cur_id),
                str(cur_begin),
                str(cur_end),
                str(cur_len),
                str(ext_id),
                str(ext_begin),
                str(ext_end),
                str(ext_len),
                str(score),
                format_float(seq_divergence),
            ]
        )
        + "\n"
        for (
            cur_id,
            cur_begin,
            cur_end,
            cur_len,
            ext_id,
            ext_begin,
            ext_end,
            ext_len,
            score,
            seq_divergence,
        ) in records
    )


def validate(path: Path, compute_canonical_sha256: bool = False) -> dict:
    raw_hasher = hashlib.sha256()
    records: list[Record] = []
    record_count = 0
    raw_sorted_by_canonical_key = True
    previous: Record | None = None
    first_record: Record | None = None
    last_record: Record | None = None

    with path.open("rb") as raw_handle:
        for line_no, raw_line in enumerate(raw_handle, 1):
            raw_hasher.update(raw_line)
            try:
                line = raw_line.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise OverlapValidationError(f"{path}:{line_no}: line is not valid UTF-8") from exc

            record = parse_record(line, line_no, path)
            if previous is not None and record < previous:
                raw_sorted_by_canonical_key = False
            previous = record
            first_record = first_record or record
            last_record = record
            record_count += 1
            if compute_canonical_sha256:
                records.append(record)

    if record_count == 0:
        raise OverlapValidationError(f"{path}: overlap dump is empty")

    summary = {
        "abi": "overlap-range-v1",
        "path": str(path.resolve()),
        "records": record_count,
        "raw_sha256": raw_hasher.hexdigest(),
        "size_bytes": path.stat().st_size,
        "raw_sorted_by_canonical_key": raw_sorted_by_canonical_key,
        "first_record": list(first_record) if first_record else None,
        "last_record": list(last_record) if last_record else None,
    }
    if compute_canonical_sha256:
        records.sort()
        summary["canonical_sha256"] = hashlib.sha256(
            canonical_text(records).encode("utf-8")
        ).hexdigest()
    return summary


def apply_expectations(summary: dict, args: argparse.Namespace) -> list[str]:
    errors = []
    if args.expect_records is not None and summary["records"] != args.expect_records:
        errors.append(f"records expected {args.expect_records}, got {summary['records']}")
    if args.expect_raw_sha256 and summary["raw_sha256"] != args.expect_raw_sha256:
        errors.append(f"raw_sha256 expected {args.expect_raw_sha256}, got {summary['raw_sha256']}")
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
    print("Overlap dump ABI: overlap-range-v1")
    print(f"  path          : {summary['path']}")
    print(f"  records       : {summary['records']}")
    print(f"  size bytes    : {summary['size_bytes']}")
    print(f"  raw sha256    : {summary['raw_sha256']}")
    if "canonical_sha256" in summary:
        print(f"  canonical sha : {summary['canonical_sha256']}")
    print(f"  raw sorted    : {summary['raw_sorted_by_canonical_key']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("overlap_dump", help="Overlap range TSV path")
    parser.add_argument("--compute-canonical-sha256", action="store_true")
    parser.add_argument("--expect-records", type=int)
    parser.add_argument("--expect-raw-sha256")
    parser.add_argument("--expect-canonical-sha256")
    parser.add_argument("--require-canonical-order", action="store_true")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary to this path")
    args = parser.parse_args(argv)

    try:
        summary = validate(
            Path(args.overlap_dump),
            compute_canonical_sha256=args.compute_canonical_sha256,
        )
        expectation_errors = apply_expectations(summary, args)
    except OverlapValidationError as exc:
        print(f"Overlap dump validation failed: {exc}", file=sys.stderr)
        return 1

    if args.json_output:
        Path(args.json_output).write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print_report(summary)

    if expectation_errors:
        for error in expectation_errors:
            print(f"Expectation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
