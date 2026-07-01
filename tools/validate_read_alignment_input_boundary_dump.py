#!/usr/bin/env python3
"""Validate cuFlye read-to-graph input-boundary TSV dumps."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import sys


ABI = "read-to-graph-input-boundary-v0"
SCHEMA_COMMENT = "# schema=cuflye-read-to-graph-input-boundary-v0"
HEADER = (
    "record_type",
    "query_id",
    "order",
    "raw_overlap_count",
    "chain_input_count",
    "read_id",
    "read_begin",
    "read_end",
    "read_len",
    "edge_seq_id",
    "edge_begin",
    "edge_end",
    "edge_len",
    "edge_id",
    "score",
    "seq_divergence",
    "passes_chain_input_filter",
    "quick_overlap_wall_ms",
    "input_filter_sort_wall_ms",
    "cpu_chain_dp_wall_ms",
    "cpu_divergence_filter_wall_ms",
)
STABLE_HEADER = HEADER[:17]
RECORD_TYPE_ORDER = {
    "query_summary": 0,
    "raw_overlap": 1,
    "chain_input": 2,
}
INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1


class InputBoundaryValidationError(ValueError):
    pass


@dataclass(frozen=True)
class InputBoundaryRecord:
    record_type: str
    query_id: int
    order: int
    raw_overlap_count: int
    chain_input_count: int
    read_id: int
    read_begin: int
    read_end: int
    read_len: int
    edge_seq_id: int
    edge_begin: int
    edge_end: int
    edge_len: int
    edge_id: int
    score: int
    seq_divergence: float
    passes_chain_input_filter: bool
    quick_overlap_wall_ms: float
    input_filter_sort_wall_ms: float
    cpu_chain_dp_wall_ms: float
    cpu_divergence_filter_wall_ms: float

    def stable_values(self) -> tuple[str, ...]:
        return (
            self.record_type,
            str(self.query_id),
            str(self.order),
            str(self.raw_overlap_count),
            str(self.chain_input_count),
            str(self.read_id),
            str(self.read_begin),
            str(self.read_end),
            str(self.read_len),
            str(self.edge_seq_id),
            str(self.edge_begin),
            str(self.edge_end),
            str(self.edge_len),
            str(self.edge_id),
            str(self.score),
            format_float(self.seq_divergence),
            "1" if self.passes_chain_input_filter else "0",
        )

    def stable_sort_key(self) -> tuple[object, ...]:
        return (
            self.query_id,
            RECORD_TYPE_ORDER[self.record_type],
            self.order,
            self.stable_values(),
        )

    def overlap_identity(self) -> tuple[object, ...]:
        return (
            self.read_id,
            self.read_begin,
            self.read_end,
            self.read_len,
            self.edge_seq_id,
            self.edge_begin,
            self.edge_end,
            self.edge_len,
            self.edge_id,
            self.score,
            format_float(self.seq_divergence),
        )


def format_float(value: float) -> str:
    if value == 0:
        return "0"
    return format(value, ".9g")


def parse_int(value: str, name: str, line_no: int, path: Path) -> int:
    if value.startswith("+"):
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: {name} must not include an explicit plus sign"
        )
    try:
        return int(value, 10)
    except ValueError as exc:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: {name} must be a decimal integer, got {value!r}"
        ) from exc


def parse_float(value: str, name: str, line_no: int, path: Path) -> float:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: {name} must be a finite float, got {value!r}"
        ) from exc
    if not math.isfinite(parsed):
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: {name} must be finite, got {value!r}"
        )
    return parsed


def parse_bool(value: str, name: str, line_no: int, path: Path) -> bool:
    if value == "0":
        return False
    if value == "1":
        return True
    raise InputBoundaryValidationError(
        f"{path}:{line_no}: {name} must be 0 or 1, got {value!r}"
    )


def parse_record(line: str, line_no: int, path: Path) -> InputBoundaryRecord:
    if not line.endswith("\n"):
        raise InputBoundaryValidationError(f"{path}:{line_no}: line must end with LF")
    fields = line[:-1].split("\t")
    if len(fields) != len(HEADER):
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: expected {len(HEADER)} tab-separated fields, "
            f"got {len(fields)}"
        )

    record_type = fields[0]
    if record_type not in RECORD_TYPE_ORDER:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: unsupported record_type {record_type!r}"
        )

    int_names = HEADER[1:15]
    ints = [
        parse_int(value, name, line_no, path)
        for value, name in zip(fields[1:15], int_names)
    ]
    seq_divergence = parse_float(fields[15], "seq_divergence", line_no, path)
    passes_filter = parse_bool(
        fields[16], "passes_chain_input_filter", line_no, path
    )
    timings = [
        parse_float(value, name, line_no, path)
        for value, name in zip(fields[17:], HEADER[17:])
    ]

    record = InputBoundaryRecord(
        record_type=record_type,
        query_id=ints[0],
        order=ints[1],
        raw_overlap_count=ints[2],
        chain_input_count=ints[3],
        read_id=ints[4],
        read_begin=ints[5],
        read_end=ints[6],
        read_len=ints[7],
        edge_seq_id=ints[8],
        edge_begin=ints[9],
        edge_end=ints[10],
        edge_len=ints[11],
        edge_id=ints[12],
        score=ints[13],
        seq_divergence=seq_divergence,
        passes_chain_input_filter=passes_filter,
        quick_overlap_wall_ms=timings[0],
        input_filter_sort_wall_ms=timings[1],
        cpu_chain_dp_wall_ms=timings[2],
        cpu_divergence_filter_wall_ms=timings[3],
    )
    validate_record(record, line_no, path)
    return record


def validate_record(record: InputBoundaryRecord, line_no: int, path: Path) -> None:
    for name in ("query_id", "read_id", "edge_seq_id", "edge_id", "score"):
        value = getattr(record, name)
        if not INT64_MIN <= value <= INT64_MAX:
            raise InputBoundaryValidationError(
                f"{path}:{line_no}: {name} is outside int64 range"
            )
    if record.query_id == 0:
        raise InputBoundaryValidationError(f"{path}:{line_no}: query_id must not be zero")
    for name in ("order", "raw_overlap_count", "chain_input_count"):
        if getattr(record, name) < 0:
            raise InputBoundaryValidationError(
                f"{path}:{line_no}: {name} must be non-negative"
            )
    if record.seq_divergence < 0:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: seq_divergence must be non-negative"
        )
    for name in HEADER[17:]:
        if getattr(record, name) < 0:
            raise InputBoundaryValidationError(
                f"{path}:{line_no}: {name} must be non-negative"
            )

    if record.record_type == "query_summary":
        stable_zero_fields = (
            "order",
            "read_id",
            "read_begin",
            "read_end",
            "read_len",
            "edge_seq_id",
            "edge_begin",
            "edge_end",
            "edge_len",
            "edge_id",
            "score",
        )
        for name in stable_zero_fields:
            if getattr(record, name) != 0:
                raise InputBoundaryValidationError(
                    f"{path}:{line_no}: query_summary {name} must be zero"
                )
        if record.seq_divergence != 0 or record.passes_chain_input_filter:
            raise InputBoundaryValidationError(
                f"{path}:{line_no}: query_summary stable payload must be zero"
            )
        return

    for name in ("read_id", "edge_seq_id", "edge_id"):
        if getattr(record, name) == 0:
            raise InputBoundaryValidationError(
                f"{path}:{line_no}: {name} must not be zero"
            )
    if record.read_len <= 0 or record.edge_len <= 0:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: read_len and edge_len must be positive"
        )
    for name in ("read_begin", "read_end", "edge_begin", "edge_end"):
        if getattr(record, name) < 0:
            raise InputBoundaryValidationError(
                f"{path}:{line_no}: {name} must be non-negative"
            )
    if record.read_begin > record.read_end or record.read_end >= record.read_len:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: read range must satisfy 0 <= begin <= end < len"
        )
    if record.edge_begin > record.edge_end or record.edge_end >= record.edge_len:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: edge range must satisfy 0 <= begin <= end < len"
        )
    if record.record_type == "chain_input" and not record.passes_chain_input_filter:
        raise InputBoundaryValidationError(
            f"{path}:{line_no}: chain_input records must pass the input filter"
        )


def read_records(path: Path) -> list[InputBoundaryRecord]:
    with path.open("r", encoding="utf-8") as handle:
        schema = handle.readline()
        if schema != SCHEMA_COMMENT + "\n":
            raise InputBoundaryValidationError(
                f"{path}: expected first line {SCHEMA_COMMENT!r}"
            )
        header = handle.readline()
        if header.rstrip("\n").split("\t") != list(HEADER):
            raise InputBoundaryValidationError(f"{path}: unexpected header line")
        records = [
            parse_record(line, line_no, path)
            for line_no, line in enumerate(handle, 3)
            if line
        ]
    if not records:
        raise InputBoundaryValidationError(f"{path}: input-boundary dump is empty")
    validate_query_groups(records, path)
    return records


def validate_query_groups(records: list[InputBoundaryRecord], path: Path) -> None:
    by_query: dict[int, list[InputBoundaryRecord]] = defaultdict(list)
    for record in records:
        by_query[record.query_id].append(record)

    for query_id, query_records in by_query.items():
        summaries = [r for r in query_records if r.record_type == "query_summary"]
        raw_records = [r for r in query_records if r.record_type == "raw_overlap"]
        chain_records = [r for r in query_records if r.record_type == "chain_input"]
        if len(summaries) != 1:
            raise InputBoundaryValidationError(
                f"{path}: query {query_id} must have exactly one query_summary"
            )
        summary = summaries[0]
        if len(raw_records) != summary.raw_overlap_count:
            raise InputBoundaryValidationError(
                f"{path}: query {query_id} raw_overlap_count expected "
                f"{summary.raw_overlap_count}, got {len(raw_records)}"
            )
        if len(chain_records) != summary.chain_input_count:
            raise InputBoundaryValidationError(
                f"{path}: query {query_id} chain_input_count expected "
                f"{summary.chain_input_count}, got {len(chain_records)}"
            )
        for record in query_records:
            if record.raw_overlap_count != summary.raw_overlap_count:
                raise InputBoundaryValidationError(
                    f"{path}: query {query_id} has inconsistent raw_overlap_count"
                )
            if record.chain_input_count != summary.chain_input_count:
                raise InputBoundaryValidationError(
                    f"{path}: query {query_id} has inconsistent chain_input_count"
                )
        if sorted(r.order for r in raw_records) != list(range(len(raw_records))):
            raise InputBoundaryValidationError(
                f"{path}: query {query_id} raw_overlap order is not contiguous"
            )
        if sorted(r.order for r in chain_records) != list(range(len(chain_records))):
            raise InputBoundaryValidationError(
                f"{path}: query {query_id} chain_input order is not contiguous"
            )
        if sum(1 for r in raw_records if r.passes_chain_input_filter) != len(chain_records):
            raise InputBoundaryValidationError(
                f"{path}: query {query_id} filtered raw overlap count does not "
                "match chain_input_count"
            )

        raw_passed = Counter(
            r.overlap_identity() for r in raw_records if r.passes_chain_input_filter
        )
        chain_inputs = Counter(r.overlap_identity() for r in chain_records)
        if chain_inputs - raw_passed:
            raise InputBoundaryValidationError(
                f"{path}: query {query_id} chain_input is not a subset of passed raw overlaps"
            )


def canonical_text(records: list[InputBoundaryRecord]) -> str:
    rows = [SCHEMA_COMMENT, "\t".join(STABLE_HEADER)]
    rows.extend("\t".join(record.stable_values()) for record in sorted(records, key=lambda r: r.stable_sort_key()))
    return "\n".join(rows) + "\n"


def validate(path: Path, compute_canonical_sha256: bool = False) -> dict:
    records = read_records(path)
    query_ids = {record.query_id for record in records}
    raw_records = [record for record in records if record.record_type == "raw_overlap"]
    chain_records = [record for record in records if record.record_type == "chain_input"]
    summary_records = [
        record for record in records if record.record_type == "query_summary"
    ]
    timing_totals = {
        "total_quick_overlap_wall_ms": sum(
            record.quick_overlap_wall_ms for record in summary_records
        ),
        "total_input_filter_sort_wall_ms": sum(
            record.input_filter_sort_wall_ms for record in summary_records
        ),
        "total_cpu_chain_dp_wall_ms": sum(
            record.cpu_chain_dp_wall_ms for record in summary_records
        ),
        "total_cpu_divergence_filter_wall_ms": sum(
            record.cpu_divergence_filter_wall_ms for record in summary_records
        ),
    }
    result = {
        "abi": ABI,
        "path": str(path.resolve()),
        "records": len(records),
        "query_summary_records": len(summary_records),
        "raw_overlap_records": len(raw_records),
        "chain_input_records": len(chain_records),
        "queries": len(query_ids),
        "queries_with_raw_overlap": len({record.query_id for record in raw_records}),
        "queries_with_chain_input": len({record.query_id for record in chain_records}),
        "canonical_timing_excluded": True,
        **timing_totals,
    }
    if compute_canonical_sha256:
        result["canonical_sha256"] = hashlib.sha256(
            canonical_text(records).encode("utf-8")
        ).hexdigest()
    return result


def apply_expectations(summary: dict, args: argparse.Namespace) -> list[str]:
    errors: list[str] = []
    if args.expect_queries is not None and summary["queries"] != args.expect_queries:
        errors.append(f"queries expected {args.expect_queries}, got {summary['queries']}")
    if (
        args.expect_chain_input_records is not None
        and summary["chain_input_records"] != args.expect_chain_input_records
    ):
        errors.append(
            "chain_input_records expected "
            f"{args.expect_chain_input_records}, got {summary['chain_input_records']}"
        )
    if args.expect_canonical_sha256:
        actual = summary.get("canonical_sha256")
        if actual is None:
            errors.append("--expect-canonical-sha256 requires --compute-canonical-sha256")
        elif actual != args.expect_canonical_sha256:
            errors.append(
                f"canonical_sha256 expected {args.expect_canonical_sha256}, got {actual}"
            )
    return errors


def print_report(summary: dict) -> None:
    print(f"Read-to-graph input-boundary ABI: {ABI}")
    print(f"  path                 : {summary['path']}")
    print(f"  records              : {summary['records']}")
    print(f"  queries              : {summary['queries']}")
    print(f"  raw overlap records  : {summary['raw_overlap_records']}")
    print(f"  chain input records  : {summary['chain_input_records']}")
    print(f"  timing excluded hash : {summary['canonical_timing_excluded']}")
    if "canonical_sha256" in summary:
        print(f"  canonical sha        : {summary['canonical_sha256']}")
    print(f"  quick overlap ms     : {summary['total_quick_overlap_wall_ms']:.6f}")
    print(f"  filter/sort ms       : {summary['total_input_filter_sort_wall_ms']:.6f}")
    print(f"  chain DP ms          : {summary['total_cpu_chain_dp_wall_ms']:.6f}")
    print(f"  divergence ms        : {summary['total_cpu_divergence_filter_wall_ms']:.6f}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_boundary_dump", help="Input-boundary TSV path")
    parser.add_argument("--compute-canonical-sha256", action="store_true")
    parser.add_argument("--json", action="store_true", help="Emit JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary to path")
    parser.add_argument("--expect-queries", type=int)
    parser.add_argument("--expect-chain-input-records", type=int)
    parser.add_argument("--expect-canonical-sha256")
    args = parser.parse_args(argv)

    try:
        summary = validate(
            Path(args.input_boundary_dump),
            compute_canonical_sha256=args.compute_canonical_sha256,
        )
        errors = apply_expectations(summary, args)
    except InputBoundaryValidationError as exc:
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

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
