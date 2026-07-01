#!/usr/bin/env python3
"""Select read-to-graph source-pack queries with chain-input-positive rows."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, Iterable, List


RAW_SCHEMA = "# schema=cuflye-read-to-graph-raw-overlap-v0"
RAW_HEADER = [
    "query_id",
    "source_order",
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
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Scan a cuFlye read-to-graph source pack and select query ids with "
            "nonzero passes_chain_input_filter rows."
        )
    )
    parser.add_argument("source_pack_dir", type=Path)
    parser.add_argument("--min-chain-input-rows", type=int, default=1)
    parser.add_argument("--max-queries", type=int, default=8)
    parser.add_argument("--max-total-raw-rows", type=int, default=5000)
    parser.add_argument("--require-positive", action="store_true")
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--query-ids-output", type=Path)
    return parser.parse_args()


def data_lines(path: Path) -> Iterable[List[str]]:
    with path.open(encoding="utf-8") as handle:
        schema = handle.readline().rstrip("\n")
        if schema != RAW_SCHEMA:
            raise ValueError(f"{path}: unexpected schema {schema!r}")
        header = handle.readline().rstrip("\n").split("\t")
        if header != RAW_HEADER:
            raise ValueError(f"{path}: unexpected raw-overlap header")
        for line_no, line in enumerate(handle, start=3):
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) != len(RAW_HEADER):
                raise ValueError(
                    f"{path}:{line_no}: expected {len(RAW_HEADER)} fields, "
                    f"got {len(fields)}"
                )
            yield fields


def query_id_from_dir(query_dir: Path) -> int:
    name = query_dir.name
    if not name.startswith("query_"):
        raise ValueError(f"unexpected query directory name: {query_dir}")
    return int(name.split("_", 1)[1])


def summarize_query(query_dir: Path) -> Dict[str, Any]:
    raw_path = query_dir / "raw-overlaps.tsv"
    if not raw_path.exists():
        raise ValueError(f"{query_dir}: missing raw-overlaps.tsv")
    query_id = query_id_from_dir(query_dir)
    raw_rows = 0
    chain_input_rows = 0
    unresolved_edge_id_zero_rows = 0
    resolved_edge_id_rows = 0
    observed_query_ids = set()
    for fields in data_lines(raw_path):
        observed_query_ids.add(int(fields[0]))
        raw_rows += 1
        if fields[15] == "1":
            chain_input_rows += 1
        elif fields[15] != "0":
            raise ValueError(
                f"{raw_path}: passes_chain_input_filter must be 0 or 1"
            )
        if int(fields[12]) == 0:
            unresolved_edge_id_zero_rows += 1
        else:
            resolved_edge_id_rows += 1
    if observed_query_ids and observed_query_ids != {query_id}:
        raise ValueError(
            f"{raw_path}: query ids {sorted(observed_query_ids)} do not match "
            f"directory query id {query_id}"
        )
    return {
        "query_id": query_id,
        "query_dir": str(query_dir),
        "raw_rows": raw_rows,
        "chain_input_rows": chain_input_rows,
        "unresolved_edge_id_zero_rows": unresolved_edge_id_zero_rows,
        "resolved_edge_id_rows": resolved_edge_id_rows,
        "selected": False,
    }


def select_queries(
    query_summaries: List[Dict[str, Any]],
    min_chain_input_rows: int,
    max_queries: int,
    max_total_raw_rows: int,
) -> List[Dict[str, Any]]:
    positives = [
        item
        for item in query_summaries
        if item["chain_input_rows"] >= min_chain_input_rows
    ]
    positives.sort(key=lambda item: item["query_id"])
    selected: List[Dict[str, Any]] = []
    total_raw_rows = 0
    for item in positives:
        if len(selected) >= max_queries:
            break
        if total_raw_rows + item["raw_rows"] > max_total_raw_rows:
            continue
        selected.append(item)
        total_raw_rows += item["raw_rows"]
    selected_ids = {item["query_id"] for item in selected}
    for item in query_summaries:
        item["selected"] = item["query_id"] in selected_ids
    return selected


def main() -> int:
    args = parse_args()
    if args.min_chain_input_rows < 1:
        raise SystemExit("--min-chain-input-rows must be >= 1")
    if args.max_queries < 1:
        raise SystemExit("--max-queries must be >= 1")
    if args.max_total_raw_rows < 1:
        raise SystemExit("--max-total-raw-rows must be >= 1")

    source_pack_dir = args.source_pack_dir
    query_dirs = sorted(
        (path for path in source_pack_dir.iterdir() if path.name.startswith("query_")),
        key=query_id_from_dir,
    )
    query_summaries = [summarize_query(path) for path in query_dirs]
    selected = select_queries(
        query_summaries,
        args.min_chain_input_rows,
        args.max_queries,
        args.max_total_raw_rows,
    )
    selected_ids = [item["query_id"] for item in selected]
    selected_csv = ",".join(str(query_id) for query_id in selected_ids)
    if args.require_positive and not selected_ids:
        raise SystemExit("no chain-input-positive query ids selected")

    payload: Dict[str, Any] = {
        "schema": "cuflye-read-to-graph-chain-input-positive-selection-v0",
        "source_pack_dir": str(source_pack_dir),
        "min_chain_input_rows": args.min_chain_input_rows,
        "max_queries": args.max_queries,
        "max_total_raw_rows": args.max_total_raw_rows,
        "total_queries": len(query_summaries),
        "positive_queries": sum(
            1
            for item in query_summaries
            if item["chain_input_rows"] >= args.min_chain_input_rows
        ),
        "selected_query_count": len(selected_ids),
        "selected_query_ids": selected_ids,
        "selected_query_ids_csv": selected_csv,
        "selected_total_raw_rows": sum(item["raw_rows"] for item in selected),
        "selected_total_chain_input_rows": sum(
            item["chain_input_rows"] for item in selected
        ),
        "queries": query_summaries,
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        args.json_output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    if args.query_ids_output:
        args.query_ids_output.write_text(selected_csv + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
