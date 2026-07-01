#!/usr/bin/env python3
"""Summarize M7d selected CPU-skip timing proof inputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

from validate_read_alignment_input_boundary_dump import read_records


SCHEMA = "cuflye-m7d-read-to-graph-selected-cpu-skip-timing-summary-v0"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def parse_query_ids(raw: str) -> list[int]:
    query_ids = [int(part) for part in raw.split(",") if part]
    if not query_ids:
        raise ValueError("--query-ids must include at least one query id")
    return query_ids


def selected_cpu_control_timing(path: Path, query_ids: list[int]) -> dict[str, Any]:
    wanted = set(query_ids)
    summaries = [
        record
        for record in read_records(path)
        if record.record_type == "query_summary" and record.query_id in wanted
    ]
    found = {record.query_id for record in summaries}
    missing = sorted(wanted - found)
    return {
        "path": str(path.resolve()),
        "selected_query_count": len(summaries),
        "missing_query_ids": missing,
        "raw_overlap_records": sum(record.raw_overlap_count for record in summaries),
        "chain_input_records": sum(record.chain_input_count for record in summaries),
        "quick_overlap_wall_ms": sum(record.quick_overlap_wall_ms for record in summaries),
        "input_filter_sort_wall_ms": sum(
            record.input_filter_sort_wall_ms for record in summaries
        ),
        "cpu_chain_dp_wall_ms": sum(record.cpu_chain_dp_wall_ms for record in summaries),
        "cpu_divergence_filter_wall_ms": sum(
            record.cpu_divergence_filter_wall_ms for record in summaries
        ),
    }


def timing_value(payload: dict[str, Any], name: str) -> float:
    value = payload.get(name, 0.0)
    return float(value or 0.0)


def summarize(args: argparse.Namespace) -> dict[str, Any]:
    query_ids = parse_query_ids(args.query_ids)
    cpu_control = selected_cpu_control_timing(
        Path(args.cpu_control_input_boundary), query_ids
    )
    canary = load_json(Path(args.positive_canary_json))
    dry_run = load_json(Path(args.positive_dry_run_json))
    worker_response = load_json(Path(args.positive_worker_response_json))

    canary_timing = canary.get("timing_ms", {})
    worker_timing = worker_response.get("timing_ms", {})
    cpu_control_total_ms = (
        cpu_control["cpu_chain_dp_wall_ms"]
        + cpu_control["cpu_divergence_filter_wall_ms"]
    )
    graph_fill_total_ms = (
        timing_value(canary_timing, "selected_cpu_skip_placeholder")
        + timing_value(canary_timing, "rebuild")
        + timing_value(canary_timing, "compare")
        + timing_value(canary_timing, "substitution")
    )
    cuda_request_total_ms = timing_value(worker_timing, "request_total")
    cuda_kernel_ms = timing_value(worker_timing, "kernel")
    cold_cuda_path_total_ms = cuda_request_total_ms + graph_fill_total_ms
    hot_kernel_plus_graph_ms = cuda_kernel_ms + graph_fill_total_ms

    checks = {
        "cpu_control_has_all_selected_queries": not cpu_control["missing_query_ids"],
        "canary_status_passed": canary.get("status") == "passed",
        "canary_consumed": canary.get("selected_cpu_skip_canary_consumed") is True,
        "selected_query_counts_match": canary.get("selected_cpu_skipped_queries")
        == len(query_ids),
        "cpu_slice_absent": canary.get("cpu_slice_chains") == 0
        and canary.get("cpu_slice_records") == 0,
        "canonical_canary_records_match": canary.get(
            "final_alignment_records_matched"
        )
        is True,
        "worker_response_ok": worker_response.get("status") == "ok",
        "dry_run_consumed_worker_output": dry_run.get(
            "graph_mutation_consumed_worker_output"
        )
        is True,
        "placeholder_timing_recorded": "selected_cpu_skip_placeholder"
        in canary_timing,
    }

    return {
        "schema": SCHEMA,
        "query_ids": query_ids,
        "cpu_control": {
            **cpu_control,
            "cpu_chain_plus_divergence_wall_ms": cpu_control_total_ms,
        },
        "cuda_path": {
            "worker_response_json": str(
                Path(args.positive_worker_response_json).resolve()
            ),
            "canary_json": str(Path(args.positive_canary_json).resolve()),
            "dry_run_json": str(Path(args.positive_dry_run_json).resolve()),
            "selected_cpu_skipped_queries": canary.get(
                "selected_cpu_skipped_queries"
            ),
            "worker_records": canary.get("worker_records"),
            "chain_input_rows": canary.get("chain_input_rows"),
            "rebuilt_good_chains": canary.get("rebuilt_good_chains"),
            "placeholder_forward_chains_filled": canary.get(
                "placeholder_forward_chains_filled"
            ),
            "placeholder_complement_chains_filled": canary.get(
                "placeholder_complement_chains_filled"
            ),
            "placeholder_insert_wall_ms": timing_value(
                canary_timing, "selected_cpu_skip_placeholder"
            ),
            "canary_rebuild_wall_ms": timing_value(canary_timing, "rebuild"),
            "canary_compare_wall_ms": timing_value(canary_timing, "compare"),
            "canary_substitution_wall_ms": timing_value(
                canary_timing, "substitution"
            ),
            "canary_total_wall_ms": timing_value(canary_timing, "total"),
            "worker_request_total_ms": cuda_request_total_ms,
            "worker_kernel_ms": cuda_kernel_ms,
            "worker_parse_ms": timing_value(worker_timing, "parse"),
            "worker_host_pack_ms": timing_value(worker_timing, "host_pack"),
            "worker_device_allocation_ms": timing_value(
                worker_timing, "device_allocation"
            ),
            "worker_h2d_ms": timing_value(worker_timing, "host_to_device"),
            "worker_d2h_ms": timing_value(worker_timing, "device_to_host"),
            "worker_write_output_ms": timing_value(worker_timing, "write_output"),
            "graph_fill_total_ms": graph_fill_total_ms,
            "cold_cuda_path_total_ms": cold_cuda_path_total_ms,
            "hot_kernel_plus_graph_ms": hot_kernel_plus_graph_ms,
        },
        "roi": {
            "cpu_control_selected_ms": cpu_control_total_ms,
            "cold_cuda_path_total_ms": cold_cuda_path_total_ms,
            "hot_kernel_plus_graph_ms": hot_kernel_plus_graph_ms,
            "cold_cuda_path_faster_than_selected_cpu_control": (
                cold_cuda_path_total_ms < cpu_control_total_ms
            ),
            "hot_kernel_plus_graph_faster_than_selected_cpu_control": (
                hot_kernel_plus_graph_ms < cpu_control_total_ms
            ),
            "cold_cuda_over_cpu_ratio": (
                cold_cuda_path_total_ms / cpu_control_total_ms
                if cpu_control_total_ms > 0
                else None
            ),
            "hot_kernel_plus_graph_over_cpu_ratio": (
                hot_kernel_plus_graph_ms / cpu_control_total_ms
                if cpu_control_total_ms > 0
                else None
            ),
        },
        "checks": checks,
        "summary_checks_passed": sum(1 for value in checks.values() if value),
        "summary_checks_required": len(checks),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpu-control-input-boundary", required=True)
    parser.add_argument("--positive-canary-json", required=True)
    parser.add_argument("--positive-dry-run-json", required=True)
    parser.add_argument("--positive-worker-response-json", required=True)
    parser.add_argument("--query-ids", required=True)
    parser.add_argument("--json-output")
    args = parser.parse_args(argv)

    summary = summarize(args)
    text = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        Path(args.json_output).write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0 if summary["summary_checks_passed"] == summary["summary_checks_required"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
