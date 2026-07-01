#!/usr/bin/env python3
"""Export deterministic M6b read-to-graph input-boundary replay packs."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import shutil
import sys
from typing import Any

from validate_read_alignment_input_boundary_dump import (
    InputBoundaryRecord,
    canonical_text as input_boundary_canonical_text,
    format_float,
    read_records,
    validate,
)


PACK_SCHEMA = "cuflye-read-to-graph-input-boundary-replay-pack-v0"
CHAIN_INPUT_SCHEMA = "# schema=cuflye-read-to-graph-chain-input-v0"
RAW_OVERLAP_SCHEMA = "# schema=cuflye-read-to-graph-raw-overlap-v0"
QUERY_SCHEMA = "# schema=cuflye-read-to-graph-input-boundary-query-v0"
CHAIN_HEADER = (
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
)
RAW_HEADER = (
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
)
QUERY_HEADER = (
    "query_id",
    "raw_overlap_count",
    "chain_input_count",
    "filtered_out_raw_overlap_count",
    "quick_overlap_wall_ms",
    "input_filter_sort_wall_ms",
    "cpu_chain_dp_wall_ms",
    "cpu_divergence_filter_wall_ms",
)


@dataclass(frozen=True)
class QueryGroup:
    query_id: int
    summary: InputBoundaryRecord
    raw_overlaps: tuple[InputBoundaryRecord, ...]
    chain_inputs: tuple[InputBoundaryRecord, ...]

    @property
    def filtered_out_count(self) -> int:
        return sum(1 for record in self.raw_overlaps if not record.passes_chain_input_filter)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def stable_overlap_values(record: InputBoundaryRecord, order_field: str) -> tuple[str, ...]:
    order_value = record.order if order_field == "order" else record.order
    return (
        str(record.query_id),
        str(order_value),
        str(record.raw_overlap_count),
        str(record.chain_input_count),
        str(record.read_id),
        str(record.read_begin),
        str(record.read_end),
        str(record.read_len),
        str(record.edge_seq_id),
        str(record.edge_begin),
        str(record.edge_end),
        str(record.edge_len),
        str(record.edge_id),
        str(record.score),
        format_float(record.seq_divergence),
        "1" if record.passes_chain_input_filter else "0",
    )


def chain_input_text(records: list[InputBoundaryRecord]) -> str:
    rows = [CHAIN_INPUT_SCHEMA, "\t".join(CHAIN_HEADER)]
    rows.extend(
        "\t".join(stable_overlap_values(record, "order"))
        for record in sorted(records, key=lambda item: (item.query_id, item.order))
    )
    return "\n".join(rows) + "\n"


def raw_overlap_text(records: list[InputBoundaryRecord]) -> str:
    rows = [RAW_OVERLAP_SCHEMA, "\t".join(RAW_HEADER)]
    rows.extend(
        "\t".join(stable_overlap_values(record, "source_order"))
        for record in sorted(records, key=lambda item: (item.query_id, item.order))
    )
    return "\n".join(rows) + "\n"


def query_text(groups: list[QueryGroup]) -> str:
    rows = [QUERY_SCHEMA, "\t".join(QUERY_HEADER)]
    for group in sorted(groups, key=lambda item: item.query_id):
        summary = group.summary
        rows.append(
            "\t".join(
                (
                    str(group.query_id),
                    str(summary.raw_overlap_count),
                    str(summary.chain_input_count),
                    str(group.filtered_out_count),
                    format_float(summary.quick_overlap_wall_ms),
                    format_float(summary.input_filter_sort_wall_ms),
                    format_float(summary.cpu_chain_dp_wall_ms),
                    format_float(summary.cpu_divergence_filter_wall_ms),
                )
            )
        )
    return "\n".join(rows) + "\n"


def group_records(records: list[InputBoundaryRecord]) -> list[QueryGroup]:
    by_query: dict[int, list[InputBoundaryRecord]] = defaultdict(list)
    for record in records:
        by_query[record.query_id].append(record)

    groups: list[QueryGroup] = []
    for query_id, query_records in by_query.items():
        summaries = [record for record in query_records if record.record_type == "query_summary"]
        raw = [record for record in query_records if record.record_type == "raw_overlap"]
        chain = [record for record in query_records if record.record_type == "chain_input"]
        if len(summaries) != 1:
            raise ValueError(f"query {query_id} does not have exactly one summary")
        groups.append(
            QueryGroup(
                query_id=query_id,
                summary=summaries[0],
                raw_overlaps=tuple(sorted(raw, key=lambda item: item.order)),
                chain_inputs=tuple(sorted(chain, key=lambda item: item.order)),
            )
        )
    groups.sort(key=lambda item: item.query_id)
    return groups


def unsupported_reasons(
    group: QueryGroup,
    max_raw_overlaps: int,
    max_chain_inputs: int,
) -> list[str]:
    reasons: list[str] = []
    if group.summary.raw_overlap_count == 0:
        reasons.append("raw_overlap_count_zero")
    if group.summary.chain_input_count == 0:
        reasons.append("chain_input_count_zero")
    if group.summary.raw_overlap_count > max_raw_overlaps:
        reasons.append("raw_overlap_count_exceeds_limit")
    if group.summary.chain_input_count > max_chain_inputs:
        reasons.append("chain_input_count_exceeds_limit")
    read_begin_counts = Counter(record.read_begin for record in group.chain_inputs)
    if any(count > 1 for count in read_begin_counts.values()):
        reasons.append("duplicate_chain_input_read_begin")
    return reasons


def select_groups(
    groups: list[QueryGroup],
    requested_query_ids: list[int],
    max_queries: int,
    max_raw_overlaps: int,
    max_chain_inputs: int,
    require_filtered_out: bool,
    require_multiple_raw: bool,
) -> tuple[list[QueryGroup], list[dict[str, Any]]]:
    unsupported: list[dict[str, Any]] = []
    supported: list[QueryGroup] = []
    for group in groups:
        reasons = unsupported_reasons(group, max_raw_overlaps, max_chain_inputs)
        if reasons:
            unsupported.append(
                {
                    "query_id": group.query_id,
                    "raw_overlap_count": group.summary.raw_overlap_count,
                    "chain_input_count": group.summary.chain_input_count,
                    "reasons": reasons,
                }
            )
        else:
            supported.append(group)

    supported_by_id = {group.query_id: group for group in supported}
    if requested_query_ids:
        missing = [query_id for query_id in requested_query_ids if query_id not in supported_by_id]
        if missing:
            raise ValueError(f"requested query ids are unsupported or absent: {missing}")
        selected = [supported_by_id[query_id] for query_id in requested_query_ids]
    else:
        selected = []
        if require_filtered_out:
            filtered_group = next(
                (group for group in supported if group.filtered_out_count > 0),
                None,
            )
            if filtered_group is None:
                raise ValueError("no supported query has filtered-out raw overlaps")
            selected.append(filtered_group)
        if require_multiple_raw:
            multiple_group = next(
                (
                    group
                    for group in supported
                    if group.summary.raw_overlap_count > 1 and group not in selected
                ),
                None,
            )
            if multiple_group is None and not any(
                group.summary.raw_overlap_count > 1 for group in selected
            ):
                raise ValueError("no supported query has multiple raw overlaps")
            if multiple_group is not None:
                selected.append(multiple_group)
        for group in supported:
            if len(selected) >= max_queries:
                break
            if group not in selected:
                selected.append(group)

    if not selected:
        raise ValueError("selected query set is empty")
    if len(selected) > max_queries:
        raise ValueError(
            f"selected {len(selected)} queries, exceeding max_queries={max_queries}"
        )
    return sorted(selected, key=lambda item: item.query_id), unsupported


def per_query_manifest(group: QueryGroup) -> dict[str, Any]:
    raw_records = list(group.raw_overlaps)
    chain_records = list(group.chain_inputs)
    return {
        "query_id": group.query_id,
        "raw_overlap_count": group.summary.raw_overlap_count,
        "chain_input_count": group.summary.chain_input_count,
        "filtered_out_raw_overlap_count": group.filtered_out_count,
        "raw_overlap_sha256": sha256_text(raw_overlap_text(raw_records)),
        "chain_input_sha256": sha256_text(chain_input_text(chain_records)),
        "timing_ms": {
            "quick_overlap": group.summary.quick_overlap_wall_ms,
            "input_filter_sort": group.summary.input_filter_sort_wall_ms,
            "cpu_chain_dp": group.summary.cpu_chain_dp_wall_ms,
            "cpu_divergence_filter": group.summary.cpu_divergence_filter_wall_ms,
        },
    }


def write_pack(
    output_dir: Path,
    source_dump: Path,
    source_summary: dict[str, Any],
    source_records: list[InputBoundaryRecord],
    selected: list[QueryGroup],
    unsupported: list[dict[str, Any]],
    args: argparse.Namespace,
) -> dict[str, Any]:
    if output_dir.exists():
        if not args.force:
            raise ValueError(f"output directory already exists: {output_dir}")
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    selected_raw = [record for group in selected for record in group.raw_overlaps]
    selected_chain = [record for group in selected for record in group.chain_inputs]
    selected_query_text = query_text(selected)
    selected_raw_text = raw_overlap_text(selected_raw)
    selected_chain_text = chain_input_text(selected_chain)

    (output_dir / "queries.tsv").write_text(selected_query_text, encoding="utf-8")
    (output_dir / "raw-overlaps.tsv").write_text(selected_raw_text, encoding="utf-8")
    (output_dir / "oracle.chain-input.tsv").write_text(
        selected_chain_text, encoding="utf-8"
    )

    reason_counts = Counter(
        reason for item in unsupported for reason in item["reasons"]
    )
    manifest = {
        "schema": PACK_SCHEMA,
        "source": {
            "input_boundary_dump": str(source_dump.resolve()),
            "abi": source_summary["abi"],
            "records": source_summary["records"],
            "queries": source_summary["queries"],
            "canonical_sha256": source_summary["canonical_sha256"],
            "canonical_timing_excluded": source_summary["canonical_timing_excluded"],
            "full_canonical_sha256": sha256_text(
                input_boundary_canonical_text(source_records)
            ),
        },
        "selection": {
            "mode": "explicit-query-ids" if args.query_id else "auto-supported",
            "max_queries": args.max_queries,
            "max_raw_overlaps_per_query": args.max_raw_overlaps_per_query,
            "max_chain_inputs_per_query": args.max_chain_inputs_per_query,
            "require_filtered_out": args.require_filtered_out,
            "require_multiple_raw": args.require_multiple_raw,
            "selected_query_ids": [group.query_id for group in selected],
        },
        "files": {
            "queries_tsv": {
                "path": "queries.tsv",
                "sha256": sha256_text(selected_query_text),
            },
            "raw_overlaps_tsv": {
                "path": "raw-overlaps.tsv",
                "records": len(selected_raw),
                "sha256": sha256_text(selected_raw_text),
            },
            "oracle_chain_input_tsv": {
                "path": "oracle.chain-input.tsv",
                "records": len(selected_chain),
                "sha256": sha256_text(selected_chain_text),
            },
        },
        "selected_query_count": len(selected),
        "selected_raw_overlap_records": len(selected_raw),
        "selected_chain_input_records": len(selected_chain),
        "selected_filtered_out_raw_overlap_records": sum(
            group.filtered_out_count for group in selected
        ),
        "selected_queries": [per_query_manifest(group) for group in selected],
        "unsupported_shape_count": len(unsupported),
        "unsupported_shape_reason_counts": dict(sorted(reason_counts.items())),
        "unsupported_shape_exclusions": unsupported[: args.max_unsupported_examples],
        "unsupported_shape_exclusions_truncated": len(unsupported)
        > args.max_unsupported_examples,
        "replay_contract": {
            "filter": "passes_chain_input_filter == 1",
            "sort_key": ["query_id", "read_begin"],
            "requires_unique_chain_input_read_begin": True,
        },
        "prototype_readiness": {
            "sufficient_for": [
                "CUDA raw-overlap filter/sort replay prototype",
                "chain_input ABI production and canonical diff",
                "fail-closed unsupported-shape handling",
            ],
            "missing_for_full_candidate_minimizer_generation": [
                "query read sequence",
                "graph edge sequences",
                "VertexIndex minimizer buckets",
                "k-mer size and minimizer window parameters",
                "OverlapDetector quickSeqOverlaps internals",
            ],
        },
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_boundary_dump", help="M6a input-boundary TSV")
    parser.add_argument("--output-dir", required=True, help="Replay pack output directory")
    parser.add_argument("--query-id", action="append", type=int, default=[])
    parser.add_argument("--max-queries", type=int, default=8)
    parser.add_argument("--max-raw-overlaps-per-query", type=int, default=256)
    parser.add_argument("--max-chain-inputs-per-query", type=int, default=256)
    parser.add_argument("--require-filtered-out", action="store_true")
    parser.add_argument("--require-multiple-raw", action="store_true")
    parser.add_argument("--max-unsupported-examples", type=int, default=64)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--json", action="store_true", help="Print manifest JSON")
    args = parser.parse_args(argv)

    try:
        source_dump = Path(args.input_boundary_dump)
        source_summary = validate(source_dump, compute_canonical_sha256=True)
        source_records = read_records(source_dump)
        groups = group_records(source_records)
        selected, unsupported = select_groups(
            groups,
            args.query_id,
            args.max_queries,
            args.max_raw_overlaps_per_query,
            args.max_chain_inputs_per_query,
            args.require_filtered_out,
            args.require_multiple_raw,
        )
        manifest = write_pack(
            Path(args.output_dir),
            source_dump,
            source_summary,
            source_records,
            selected,
            unsupported,
            args,
        )
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(manifest, indent=2, sort_keys=True))
    else:
        print(f"Replay pack schema: {PACK_SCHEMA}")
        print(f"  output dir      : {Path(args.output_dir).resolve()}")
        print(f"  selected queries: {manifest['selected_query_count']}")
        print(f"  raw records     : {manifest['selected_raw_overlap_records']}")
        print(f"  chain inputs    : {manifest['selected_chain_input_records']}")
        print(f"  unsupported     : {manifest['unsupported_shape_count']}")
        print(f"  manifest        : {Path(args.output_dir).resolve() / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
