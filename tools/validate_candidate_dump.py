#!/usr/bin/env python3
"""Validate cuFlye candidate dump TSV files against ABI v1."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1
UINT64_MAX = 2**64 - 1

Record = tuple[int, int, int, int, int, str]


class CandidateValidationError(ValueError):
    pass


def parse_record(line: str, line_no: int, path: Path) -> Record:
    if not line.endswith("\n"):
        raise CandidateValidationError(f"{path}:{line_no}: line must end with LF")
    line = line[:-1]
    if not line:
        raise CandidateValidationError(f"{path}:{line_no}: blank records are not allowed")

    parts = line.split("\t")
    if len(parts) != 6:
        raise CandidateValidationError(
            f"{path}:{line_no}: expected 6 tab-separated fields, got {len(parts)}"
        )

    names = ("query_id", "query_pos", "kmer", "target_id", "target_pos", "target_strand")
    values: list[int | str] = []
    for index, (name, value) in enumerate(zip(names, parts)):
        if index == 5:
            if value not in {"+", "-"}:
                raise CandidateValidationError(
                    f"{path}:{line_no}: target_strand must be '+' or '-', got {value!r}"
                )
            values.append(value)
            continue
        if value.startswith("+"):
            raise CandidateValidationError(
                f"{path}:{line_no}: {name} must not include an explicit plus sign"
            )
        try:
            parsed = int(value, 10)
        except ValueError as exc:
            raise CandidateValidationError(
                f"{path}:{line_no}: {name} must be a decimal integer, got {value!r}"
            ) from exc
        values.append(parsed)

    query_id, query_pos, kmer, target_id, target_pos, strand = values
    assert isinstance(query_id, int)
    assert isinstance(query_pos, int)
    assert isinstance(kmer, int)
    assert isinstance(target_id, int)
    assert isinstance(target_pos, int)
    assert isinstance(strand, str)

    if not INT64_MIN <= query_id <= INT64_MAX:
        raise CandidateValidationError(f"{path}:{line_no}: query_id is outside int64 range")
    if not INT64_MIN <= target_id <= INT64_MAX:
        raise CandidateValidationError(f"{path}:{line_no}: target_id is outside int64 range")
    if not 0 <= query_pos <= INT64_MAX:
        raise CandidateValidationError(f"{path}:{line_no}: query_pos is outside uint63 range")
    if not 0 <= target_pos <= INT64_MAX:
        raise CandidateValidationError(f"{path}:{line_no}: target_pos is outside uint63 range")
    if not 0 <= kmer <= UINT64_MAX:
        raise CandidateValidationError(f"{path}:{line_no}: kmer is outside uint64 range")

    return query_id, query_pos, kmer, target_id, target_pos, strand


def canonical_text(records: list[Record]) -> str:
    return "".join(
        f"{query_id}\t{query_pos}\t{kmer}\t{target_id}\t{target_pos}\t{strand}\n"
        for query_id, query_pos, kmer, target_id, target_pos, strand in records
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
                raise CandidateValidationError(f"{path}:{line_no}: line is not valid UTF-8") from exc

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
        raise CandidateValidationError(f"{path}: candidate dump is empty")

    summary = {
        "abi": "candidate-record-v1",
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
    print("Candidate dump ABI: candidate-record-v1")
    print(f"  path          : {summary['path']}")
    print(f"  records       : {summary['records']}")
    print(f"  size bytes    : {summary['size_bytes']}")
    print(f"  raw sha256    : {summary['raw_sha256']}")
    if "canonical_sha256" in summary:
        print(f"  canonical sha : {summary['canonical_sha256']}")
    print(f"  raw sorted    : {summary['raw_sorted_by_canonical_key']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate_dump", help="Candidate dump TSV path")
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
            Path(args.candidate_dump),
            compute_canonical_sha256=args.compute_canonical_sha256,
        )
        expectation_errors = apply_expectations(summary, args)
    except CandidateValidationError as exc:
        print(f"Candidate dump validation failed: {exc}", file=sys.stderr)
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
