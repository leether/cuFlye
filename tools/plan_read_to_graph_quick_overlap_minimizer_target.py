#!/usr/bin/env python3
"""Plan the M8a quick-overlap/minimizer CUDA target."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys
from typing import Any

from export_read_to_graph_input_boundary_pack import (
    QueryGroup,
    group_records,
    unsupported_reasons,
    write_pack,
)
from validate_read_alignment_input_boundary_dump import read_records, validate


SCHEMA = "cuflye-m8a-read-to-graph-quick-overlap-minimizer-target-summary-v0"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def query_timing(group: QueryGroup) -> dict[str, float]:
    summary = group.summary
    chain_plus_divergence = (
        summary.cpu_chain_dp_wall_ms + summary.cpu_divergence_filter_wall_ms
    )
    return {
        "quick_overlap_wall_ms": summary.quick_overlap_wall_ms,
        "input_filter_sort_wall_ms": summary.input_filter_sort_wall_ms,
        "cpu_chain_dp_wall_ms": summary.cpu_chain_dp_wall_ms,
        "cpu_divergence_filter_wall_ms": summary.cpu_divergence_filter_wall_ms,
        "cpu_chain_plus_divergence_wall_ms": chain_plus_divergence,
    }


def query_row(
    group: QueryGroup, reasons: list[str] | None = None
) -> dict[str, Any]:
    unsupported_reasons = reasons or []
    return {
        "query_id": group.query_id,
        "raw_overlap_count": group.summary.raw_overlap_count,
        "chain_input_count": group.summary.chain_input_count,
        "filtered_out_raw_overlap_count": group.filtered_out_count,
        "supported": not unsupported_reasons,
        "reasons": unsupported_reasons,
        "unsupported_reasons": unsupported_reasons,
        "timing_ms": query_timing(group),
    }


def sum_query_timing(groups: list[QueryGroup]) -> dict[str, float]:
    names = (
        "quick_overlap_wall_ms",
        "input_filter_sort_wall_ms",
        "cpu_chain_dp_wall_ms",
        "cpu_divergence_filter_wall_ms",
        "cpu_chain_plus_divergence_wall_ms",
    )
    totals = {name: 0.0 for name in names}
    for group in groups:
        timing = query_timing(group)
        for name in names:
            totals[name] += timing[name]
    return totals


def load_m7d_reference(path: Path) -> dict[str, Any]:
    payload = load_json(path)
    timing_summary = payload["timing_summary"]
    roi = timing_summary["roi"]
    cpu_control = timing_summary["cpu_control"]
    cuda_path = timing_summary["cuda_path"]
    return {
        "path": str(path.resolve()),
        "schema": payload.get("schema"),
        "cpu_control_selected_chain_plus_divergence_ms": float(
            roi["cpu_control_selected_ms"]
        ),
        "cpu_control_selected_quick_overlap_ms": float(
            cpu_control["quick_overlap_wall_ms"]
        ),
        "hot_kernel_plus_graph_ms": float(cuda_path["hot_kernel_plus_graph_ms"]),
        "cold_cuda_path_total_ms": float(cuda_path["cold_cuda_path_total_ms"]),
    }


def load_m6j_reference(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    payload = load_json(path)
    session = payload["session_parallel"]
    return {
        "path": str(path.resolve()),
        "schema": payload.get("schema"),
        "cpu_replay_wall_ms": float(payload["cpu_replay_wall_ms"]),
        "warm_request_total_best_ms": float(
            session["warm_request_total_best_ms"]
        ),
        "warm_kernel_best_ms": float(session["warm_kernel_best_ms"]),
        "bounded_hot_request_speedup_vs_cpu_replay_wall": float(
            payload["timing_comparison"][
                "bounded_hot_request_speedup_vs_cpu_replay_wall"
            ]
        ),
        "source_pack_total_counts": payload["source_pack_total_counts"],
    }


def select_supported_groups(
    groups: list[QueryGroup],
    max_queries: int,
    max_raw_overlaps_per_query: int,
    max_chain_inputs_per_query: int,
) -> tuple[list[QueryGroup], list[dict[str, Any]], list[dict[str, Any]]]:
    supported: list[QueryGroup] = []
    unsupported: list[dict[str, Any]] = []
    for group in groups:
        reasons = unsupported_reasons(
            group,
            max_raw_overlaps_per_query,
            max_chain_inputs_per_query,
        )
        if reasons:
            unsupported.append(query_row(group, reasons))
        else:
            supported.append(group)

    supported.sort(
        key=lambda item: (-item.summary.quick_overlap_wall_ms, item.query_id)
    )
    selected = supported[:max_queries]
    candidates = [query_row(group) for group in selected]
    return selected, candidates, unsupported


def build_pack_args(
    args: argparse.Namespace, selected_query_ids: list[int]
) -> argparse.Namespace:
    return argparse.Namespace(
        force=args.force,
        query_id=selected_query_ids,
        max_queries=args.max_queries,
        max_raw_overlaps_per_query=args.max_raw_overlaps_per_query,
        max_chain_inputs_per_query=args.max_chain_inputs_per_query,
        require_filtered_out=False,
        require_multiple_raw=False,
        max_unsupported_examples=args.max_unsupported_examples,
    )


def build_cuda_contract(
    selected_timing: dict[str, float],
    m6j_reference: dict[str, Any] | None,
) -> dict[str, Any]:
    speedup_threshold = float(selected_timing["quick_overlap_wall_ms"])
    contract = {
        "next_cuda_boundary": "full-query-hit candidate discovery before raw-overlap filtering",
        "input": "cuflye-read-to-graph-minimizer-source-pack-v0 with full-query-hits.tsv",
        "output": "cuflye-read-to-graph-raw-overlap-v0 row-key parity before graph consumption",
        "correctness_gate": [
            "CPU source-pack replay row-key match",
            "CUDA row-key diff match against CPU replay",
            "M6b chain_input replay pack remains match",
            "Flye canonical artifacts remain unchanged in capture mode",
            "unsupported source-pack shapes fail closed",
        ],
        "speed_gate": {
            "baseline": "same selected queries' Flye quick_overlap_wall_ms",
            "required_hot_worker_ms_lt": speedup_threshold,
            "required_speedup_gt": 1.0,
            "preferred_speedup_gt": 1.25,
        },
    }
    if m6j_reference is not None:
        hot_ms = m6j_reference["warm_request_total_best_ms"]
        contract["reference_existing_m6j_hot_request_ms"] = hot_ms
        contract["existing_m6j_hot_request_below_m8a_selected_quick_overlap"] = (
            hot_ms < speedup_threshold
        )
    return contract


def summarize(args: argparse.Namespace) -> dict[str, Any]:
    input_boundary = Path(args.input_boundary_dump)
    source_summary = validate(input_boundary, compute_canonical_sha256=True)
    source_records = read_records(input_boundary)
    groups = group_records(source_records)
    m7d_reference = load_m7d_reference(Path(args.m7d_proof_json))
    m6j_reference = load_m6j_reference(
        Path(args.m6j_proof_json) if args.m6j_proof_json else None
    )

    selected, selected_candidates, unsupported = select_supported_groups(
        groups,
        args.max_queries,
        args.max_raw_overlaps_per_query,
        args.max_chain_inputs_per_query,
    )
    if not selected:
        raise ValueError("no supported quick-overlap target queries selected")

    selected_query_ids = [group.query_id for group in selected]
    selected_timing = sum_query_timing(selected)
    selected_raw = sum(group.summary.raw_overlap_count for group in selected)
    selected_chain = sum(group.summary.chain_input_count for group in selected)
    unsupported_reason_counts = Counter(
        reason for item in unsupported for reason in item["unsupported_reasons"]
    )

    pack_manifest = None
    if args.pack_output_dir:
        pack_manifest = write_pack(
            Path(args.pack_output_dir),
            input_boundary,
            source_summary,
            source_records,
            sorted(selected, key=lambda item: item.query_id),
            unsupported,
            build_pack_args(args, selected_query_ids),
        )

    m7d_cpu_ms = m7d_reference["cpu_control_selected_chain_plus_divergence_ms"]
    selected_vs_m7d_ratio = (
        selected_timing["quick_overlap_wall_ms"] / m7d_cpu_ms
        if m7d_cpu_ms > 0
        else None
    )
    m6j_hot_ms = (
        m6j_reference["warm_request_total_best_ms"] if m6j_reference else None
    )
    m6j_hot_vs_selected_ratio = (
        m6j_hot_ms / selected_timing["quick_overlap_wall_ms"]
        if m6j_hot_ms is not None
        and selected_timing["quick_overlap_wall_ms"] > 0
        else None
    )
    checks = {
        "input_boundary_valid": source_summary["abi"]
        == "read-to-graph-input-boundary-v0",
        "selected_query_count_positive": len(selected) > 0,
        "selected_has_raw_overlaps": selected_raw > 0,
        "selected_has_chain_inputs": selected_chain > 0,
        "selected_quick_overlap_materially_exceeds_m7d_boundary": (
            selected_vs_m7d_ratio is not None
            and selected_vs_m7d_ratio >= args.min_m7d_multiplier
        ),
        "selected_pack_written": bool(pack_manifest),
        "existing_m6j_hot_request_below_selected_quick_overlap": (
            m6j_hot_ms is not None
            and m6j_hot_ms < selected_timing["quick_overlap_wall_ms"]
        ),
    }

    return {
        "schema": SCHEMA,
        "source": {
            "input_boundary_dump": str(input_boundary.resolve()),
            **source_summary,
        },
        "selection_policy": {
            "sort": "quick_overlap_wall_ms desc, query_id asc",
            "max_queries": args.max_queries,
            "max_raw_overlaps_per_query": args.max_raw_overlaps_per_query,
            "max_chain_inputs_per_query": args.max_chain_inputs_per_query,
            "min_m7d_multiplier": args.min_m7d_multiplier,
        },
        "selected": {
            "query_ids": selected_query_ids,
            "query_count": len(selected),
            "raw_overlap_records": selected_raw,
            "chain_input_records": selected_chain,
            "timing_ms": selected_timing,
            "quick_overlap_vs_m7d_selected_chain_divergence_ratio": (
                selected_vs_m7d_ratio
            ),
            "m6j_hot_request_over_selected_quick_overlap_ratio": (
                m6j_hot_vs_selected_ratio
            ),
            "queries": selected_candidates,
        },
        "unsupported_shape": {
            "count": len(unsupported),
            "reason_counts": dict(sorted(unsupported_reason_counts.items())),
            "examples": unsupported[: args.max_unsupported_examples],
            "examples_truncated": len(unsupported)
            > args.max_unsupported_examples,
        },
        "references": {
            "m7d": m7d_reference,
            "m6j": m6j_reference,
        },
        "oracle_pack": pack_manifest,
        "cuda_target_contract": build_cuda_contract(
            selected_timing, m6j_reference
        ),
        "checks": checks,
        "summary_checks_passed": sum(1 for value in checks.values() if value),
        "summary_checks_required": len(checks),
        "allowed_claim": (
            "M8a identifies a bounded, replayable read-to-graph "
            "quick-overlap/minimizer target whose CPU-control quick-overlap "
            "time is materially larger than the M7d selected chain/divergence "
            "boundary."
        ),
        "forbidden_claim": (
            "M8a does not prove default GPU mode, graph consumption, whole-Flye "
            "speedup, or CUDA speedup for the newly selected query set."
        ),
        "next_recommended_step": (
            "M8b: capture a full-query-hit source pack for the M8a selected "
            "queries and run the warm CUDA full-query-hit replay session "
            "against the same selected quick-overlap CPU baseline."
        ),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_boundary_dump")
    parser.add_argument("--m7d-proof-json", required=True)
    parser.add_argument("--m6j-proof-json")
    parser.add_argument("--pack-output-dir")
    parser.add_argument("--max-queries", type=int, default=16)
    parser.add_argument("--max-raw-overlaps-per-query", type=int, default=4096)
    parser.add_argument("--max-chain-inputs-per-query", type=int, default=4096)
    parser.add_argument("--max-unsupported-examples", type=int, default=32)
    parser.add_argument("--min-m7d-multiplier", type=float, default=10.0)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--json-output")
    args = parser.parse_args(argv)

    try:
        summary = summarize(args)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    text = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        Path(args.json_output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json_output).write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return (
        0
        if summary["summary_checks_passed"]
        == summary["summary_checks_required"]
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
