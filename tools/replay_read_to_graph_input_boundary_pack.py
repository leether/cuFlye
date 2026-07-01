#!/usr/bin/env python3
"""Replay and diff M6b read-to-graph input-boundary replay packs."""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import difflib
import hashlib
import json
from pathlib import Path
import sys

from export_read_to_graph_input_boundary_pack import (
    CHAIN_HEADER,
    CHAIN_INPUT_SCHEMA,
    PACK_SCHEMA,
    RAW_HEADER,
    RAW_OVERLAP_SCHEMA,
    chain_input_text,
)
from validate_read_alignment_input_boundary_dump import InputBoundaryRecord


class ReplayPackError(ValueError):
    pass


@dataclass(frozen=True)
class StableOverlapRow:
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

    def to_input_boundary_record(self, record_type: str, order: int | None = None) -> InputBoundaryRecord:
        return InputBoundaryRecord(
            record_type=record_type,
            query_id=self.query_id,
            order=self.order if order is None else order,
            raw_overlap_count=self.raw_overlap_count,
            chain_input_count=self.chain_input_count,
            read_id=self.read_id,
            read_begin=self.read_begin,
            read_end=self.read_end,
            read_len=self.read_len,
            edge_seq_id=self.edge_seq_id,
            edge_begin=self.edge_begin,
            edge_end=self.edge_end,
            edge_len=self.edge_len,
            edge_id=self.edge_id,
            score=self.score,
            seq_divergence=self.seq_divergence,
            passes_chain_input_filter=self.passes_chain_input_filter,
            quick_overlap_wall_ms=0.0,
            input_filter_sort_wall_ms=0.0,
            cpu_chain_dp_wall_ms=0.0,
            cpu_divergence_filter_wall_ms=0.0,
        )


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def parse_int(value: str, name: str, path: Path, line_no: int) -> int:
    try:
        return int(value, 10)
    except ValueError as exc:
        raise ReplayPackError(
            f"{path}:{line_no}: {name} must be a decimal integer, got {value!r}"
        ) from exc


def parse_bool(value: str, name: str, path: Path, line_no: int) -> bool:
    if value == "0":
        return False
    if value == "1":
        return True
    raise ReplayPackError(f"{path}:{line_no}: {name} must be 0 or 1, got {value!r}")


def parse_stable_overlap_line(
    fields: list[str], header: tuple[str, ...], path: Path, line_no: int
) -> StableOverlapRow:
    if len(fields) != len(header):
        raise ReplayPackError(
            f"{path}:{line_no}: expected {len(header)} fields, got {len(fields)}"
        )
    values = dict(zip(header, fields))
    order_name = "source_order" if "source_order" in values else "order"
    try:
        seq_divergence = float(values["seq_divergence"])
    except ValueError as exc:
        raise ReplayPackError(
            f"{path}:{line_no}: seq_divergence must be a float"
        ) from exc
    return StableOverlapRow(
        query_id=parse_int(values["query_id"], "query_id", path, line_no),
        order=parse_int(values[order_name], order_name, path, line_no),
        raw_overlap_count=parse_int(
            values["raw_overlap_count"], "raw_overlap_count", path, line_no
        ),
        chain_input_count=parse_int(
            values["chain_input_count"], "chain_input_count", path, line_no
        ),
        read_id=parse_int(values["read_id"], "read_id", path, line_no),
        read_begin=parse_int(values["read_begin"], "read_begin", path, line_no),
        read_end=parse_int(values["read_end"], "read_end", path, line_no),
        read_len=parse_int(values["read_len"], "read_len", path, line_no),
        edge_seq_id=parse_int(values["edge_seq_id"], "edge_seq_id", path, line_no),
        edge_begin=parse_int(values["edge_begin"], "edge_begin", path, line_no),
        edge_end=parse_int(values["edge_end"], "edge_end", path, line_no),
        edge_len=parse_int(values["edge_len"], "edge_len", path, line_no),
        edge_id=parse_int(values["edge_id"], "edge_id", path, line_no),
        score=parse_int(values["score"], "score", path, line_no),
        seq_divergence=seq_divergence,
        passes_chain_input_filter=parse_bool(
            values["passes_chain_input_filter"],
            "passes_chain_input_filter",
            path,
            line_no,
        ),
    )


def read_stable_overlap_tsv(
    path: Path, schema: str, header: tuple[str, ...]
) -> list[StableOverlapRow]:
    with path.open("r", encoding="utf-8") as handle:
        first = handle.readline()
        if first != schema + "\n":
            raise ReplayPackError(f"{path}: expected schema line {schema!r}")
        second = handle.readline()
        if second.rstrip("\n").split("\t") != list(header):
            raise ReplayPackError(f"{path}: unexpected header")
        rows = []
        for line_no, line in enumerate(handle, 3):
            if not line.endswith("\n"):
                raise ReplayPackError(f"{path}:{line_no}: line must end with LF")
            rows.append(
                parse_stable_overlap_line(line[:-1].split("\t"), header, path, line_no)
            )
    return rows


def load_manifest(pack_dir: Path) -> dict:
    path = pack_dir / "manifest.json"
    with path.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("schema") != PACK_SCHEMA:
        raise ReplayPackError(
            f"{path}: unsupported schema {manifest.get('schema')!r}"
        )
    return manifest


def replay_chain_inputs(raw_rows: list[StableOverlapRow]) -> list[InputBoundaryRecord]:
    by_query: dict[int, list[StableOverlapRow]] = defaultdict(list)
    for row in raw_rows:
        by_query[row.query_id].append(row)

    replayed: list[InputBoundaryRecord] = []
    for query_id in sorted(by_query):
        filtered = [row for row in by_query[query_id] if row.passes_chain_input_filter]
        read_begins = [row.read_begin for row in filtered]
        if len(read_begins) != len(set(read_begins)):
            raise ReplayPackError(
                f"query {query_id}: duplicate read_begin values make replay order ambiguous"
            )
        filtered.sort(key=lambda row: row.read_begin)
        for order, row in enumerate(filtered):
            replayed.append(row.to_input_boundary_record("chain_input", order=order))
    return replayed


def compare_pack(pack_dir: Path, output_tsv: Path | None, include_diff: bool,
                 max_diff_lines: int) -> dict:
    manifest = load_manifest(pack_dir)
    raw_rows = read_stable_overlap_tsv(
        pack_dir / "raw-overlaps.tsv", RAW_OVERLAP_SCHEMA, RAW_HEADER
    )
    oracle_rows = read_stable_overlap_tsv(
        pack_dir / "oracle.chain-input.tsv", CHAIN_INPUT_SCHEMA, CHAIN_HEADER
    )
    replayed_records = replay_chain_inputs(raw_rows)
    oracle_records = [
        row.to_input_boundary_record("chain_input") for row in oracle_rows
    ]
    replayed_text = chain_input_text(replayed_records)
    oracle_text = chain_input_text(oracle_records)
    replayed_sha = sha256_text(replayed_text)
    oracle_sha = sha256_text(oracle_text)
    if output_tsv:
        output_tsv.parent.mkdir(parents=True, exist_ok=True)
        output_tsv.write_text(replayed_text, encoding="utf-8")
    summary = {
        "schema": "cuflye-read-to-graph-input-boundary-replay-result-v0",
        "pack_schema": manifest["schema"],
        "pack_dir": str(pack_dir.resolve()),
        "status": "match" if replayed_sha == oracle_sha else "mismatch",
        "selected_query_count": manifest["selected_query_count"],
        "raw_overlap_records": len(raw_rows),
        "oracle_chain_input_records": len(oracle_records),
        "replayed_chain_input_records": len(replayed_records),
        "oracle_chain_input_sha256": oracle_sha,
        "replayed_chain_input_sha256": replayed_sha,
        "selected_query_ids": manifest["selection"]["selected_query_ids"],
        "replay_contract": manifest["replay_contract"],
    }
    if include_diff and replayed_sha != oracle_sha:
        diff_lines = list(
            difflib.unified_diff(
                oracle_text.splitlines(keepends=True),
                replayed_text.splitlines(keepends=True),
                fromfile=str(pack_dir / "oracle.chain-input.tsv"),
                tofile=str(output_tsv or "replayed.chain-input.tsv"),
                n=3,
            )
        )
        summary["diff"] = "".join(diff_lines[:max_diff_lines])
        summary["diff_truncated"] = len(diff_lines) > max_diff_lines
    return summary


def print_report(summary: dict) -> None:
    print(f"Read-to-graph input-boundary replay: {summary['status']}")
    print(f"  pack dir       : {summary['pack_dir']}")
    print(f"  selected queries: {summary['selected_query_count']}")
    print(f"  raw records    : {summary['raw_overlap_records']}")
    print(f"  oracle records : {summary['oracle_chain_input_records']}")
    print(f"  replay records : {summary['replayed_chain_input_records']}")
    print(f"  oracle sha     : {summary['oracle_chain_input_sha256']}")
    print(f"  replay sha     : {summary['replayed_chain_input_sha256']}")
    if summary.get("diff"):
        print(summary["diff"], end="" if summary["diff"].endswith("\n") else "\n")
        if summary.get("diff_truncated"):
            print("... diff truncated ...")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack_dir", help="M6b replay pack directory")
    parser.add_argument("--output-tsv", help="Write replayed chain-input TSV")
    parser.add_argument("--json", action="store_true", help="Print JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary")
    parser.add_argument("--show-diff", action="store_true")
    parser.add_argument("--max-diff-lines", type=int, default=200)
    args = parser.parse_args(argv)

    try:
        summary = compare_pack(
            Path(args.pack_dir),
            Path(args.output_tsv) if args.output_tsv else None,
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
