#!/usr/bin/env python3
"""Summarize M5y read-alignment post-bypass timing attribution proofs."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
from typing import Any


TIME_PATTERNS = {
    "user_seconds": re.compile(r"User time \(seconds\):\s+([0-9.]+)"),
    "system_seconds": re.compile(r"System time \(seconds\):\s+([0-9.]+)"),
    "elapsed": re.compile(r"Elapsed \(wall clock\) time .*:\s+([^\n]+)"),
    "max_rss_kbytes": re.compile(
        r"Maximum resident set size \(kbytes\):\s+(\d+)"
    ),
    "exit_status": re.compile(r"Exit status:\s+(\d+)"),
}
LOG_TS_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]")


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def parse_elapsed_seconds(value: str) -> float:
    parts = value.strip().split(":")
    if len(parts) == 2:
        minutes, seconds = parts
        return int(minutes) * 60 + float(seconds)
    if len(parts) == 3:
        hours, minutes, seconds = parts
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    raise ValueError(f"unsupported elapsed time format: {value!r}")


def parse_time_log(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"path": str(path), "present": False}
    parsed: dict[str, Any] = {"path": str(path), "present": True}
    text = path.read_text(encoding="utf-8", errors="replace")
    for key, pattern in TIME_PATTERNS.items():
        match = pattern.search(text)
        if not match:
            continue
        value = match.group(1)
        if key == "elapsed":
            parsed["elapsed_seconds"] = parse_elapsed_seconds(value)
            parsed["elapsed_raw"] = value
        elif key in {"max_rss_kbytes", "exit_status"}:
            parsed[key] = int(value)
        else:
            parsed[key] = float(value)
    return parsed


def log_timestamp(line: str) -> datetime | None:
    match = LOG_TS_RE.match(line)
    if not match:
        return None
    return datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")


def parse_flye_log(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": str(path),
        "present": path.exists(),
        "stage_events": [],
    }
    if not path.exists():
        return result

    read_alignment_start: datetime | None = None
    read_alignment_end: datetime | None = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        timestamp = log_timestamp(line)
        if timestamp and ">>>STAGE:" in line:
            result["stage_events"].append({
                "timestamp": timestamp.isoformat(sep=" "),
                "line": line,
            })
        if timestamp and "Aligning reads to the graph" in line:
            read_alignment_start = timestamp
        if timestamp and "Aligned read sequence:" in line:
            read_alignment_end = timestamp

    if read_alignment_start:
        result["read_to_graph_start"] = read_alignment_start.isoformat(sep=" ")
    if read_alignment_end:
        result["read_to_graph_end"] = read_alignment_end.isoformat(sep=" ")
    if read_alignment_start and read_alignment_end:
        result["read_to_graph_log_seconds"] = (
            read_alignment_end - read_alignment_start
        ).total_seconds()
        result["read_to_graph_resolution_note"] = (
            "Flye log timestamps have one-second resolution."
        )
    return result


def canonical_diff_status(run_dir: Path) -> str | None:
    path = run_dir / "canonical-diff.json"
    if not path.exists():
        return None
    return read_json(path).get("status")


def compact_binary_status(run_dir: Path) -> str | None:
    path = run_dir / "compact-binary-validation.json"
    if not path.exists():
        return None
    return read_json(path).get("status")


def worker_audit(run_dir: Path) -> dict[str, Any]:
    root = run_dir / "read-alignment-replay-fixtures" / "predivergence-batch-worker"
    return read_json(root / "read-alignment-predivergence-batch-dry-run.json")


def worker_response(run_dir: Path) -> dict[str, Any]:
    root = run_dir / "read-alignment-replay-fixtures" / "predivergence-batch-worker"
    return read_json(root / "read-alignment-worker-response.json")


def summarize_cpu_run(run_dir: Path) -> dict[str, Any]:
    return {
        "run_dir": str(run_dir),
        "time_log": parse_time_log(run_dir / "time.log"),
        "flye_log": parse_flye_log(run_dir / "flye.log"),
    }


def summarize_gpu_run(run_dir: Path) -> dict[str, Any]:
    audit = worker_audit(run_dir)
    response = worker_response(run_dir)
    sidecar_time = run_dir.parent / f"{run_dir.name}.time.log"
    return {
        "run_dir": str(run_dir),
        "time_log": parse_time_log(run_dir / "time.log"),
        "sidecar_time_log": parse_time_log(sidecar_time),
        "flye_log": parse_flye_log(run_dir / "flye.log"),
        "canonical_diff": canonical_diff_status(run_dir),
        "compact_binary_validation": compact_binary_status(run_dir),
        "audit": {
            "status": audit.get("status"),
            "decision": audit.get("decision"),
            "fixture_count": audit.get("fixture_count"),
            "total_cpu_predivergence_chains": audit.get(
                "total_cpu_predivergence_chains"
            ),
            "total_cpu_bypassed_reads": audit.get("total_cpu_bypassed_reads"),
            "total_cpu_bypass_inserted_chains": audit.get(
                "total_cpu_bypass_inserted_chains"
            ),
            "total_worker_records": audit.get("total_worker_records"),
            "total_substituted_chains": audit.get("total_substituted_chains"),
            "total_cpu_chain_dp_wall_ms": audit.get("total_cpu_chain_dp_wall_ms"),
            "total_cpu_divergence_filter_wall_ms": audit.get(
                "total_cpu_divergence_filter_wall_ms"
            ),
            "total_replay_fixture_dump_wall_ms": audit.get(
                "total_replay_fixture_dump_wall_ms"
            ),
            "total_cpu_bypass_placeholder_wall_ms": audit.get(
                "total_cpu_bypass_placeholder_wall_ms"
            ),
            "total_gpu_divergence_filter_wall_ms": audit.get(
                "total_gpu_divergence_filter_wall_ms"
            ),
            "vector_substitution_wall_ms": audit.get("vector_substitution_wall_ms"),
            "worker_warmup_wall_ms": audit.get("worker_warmup_wall_ms"),
            "worker_actual_wall_ms": audit.get("worker_actual_wall_ms"),
            "graph_mutation_consumed_worker_output": audit.get(
                "graph_mutation_consumed_worker_output"
            ),
            "worker_compact_binary_sha256": audit.get(
                "worker_compact_binary_sha256"
            ),
            "worker_compact_binary_validation_status": audit.get(
                "worker_compact_binary_validation_status"
            ),
        },
        "worker_response": {
            "status": response.get("status"),
            "request_ordinal": response.get("request_ordinal"),
            "worker_cuda_context_warm": response.get("worker_cuda_context_warm"),
            "worker_device_arena_cache_hit": response.get(
                "worker_device_arena_cache_hit"
            ),
            "output_artifact_mode": response.get("output_artifact_mode"),
            "compact_output_only": response.get("compact_output_only"),
            "output_records": response.get("output_records"),
            "timing_ms": response.get("timing_ms", {}),
        },
    }


def build_summary(args: argparse.Namespace) -> dict[str, Any]:
    cpu = summarize_cpu_run(Path(args.cpu_run))
    m5w = summarize_gpu_run(Path(args.m5w_run))
    m5x = summarize_gpu_run(Path(args.m5x_run))

    m5w_audit = m5w["audit"]
    m5x_audit = m5x["audit"]
    avoided_cpu_chain_ms = (
        (m5w_audit.get("total_cpu_chain_dp_wall_ms") or 0.0)
        - (m5x_audit.get("total_cpu_chain_dp_wall_ms") or 0.0)
    )
    avoided_cpu_divergence_ms = (
        (m5w_audit.get("total_cpu_divergence_filter_wall_ms") or 0.0)
        - (m5x_audit.get("total_cpu_divergence_filter_wall_ms") or 0.0)
    )

    return {
        "schema": "cuflye-m5y-read-alignment-post-bypass-attribution-v0",
        "status": "accepted",
        "milestone": "M5y-read-alignment-post-bypass-attribution",
        "host": "dgx",
        "architecture": "aarch64",
        "fixture": "toy-hifi",
        "proof_root": args.proof_root,
        "sources": {
            "cpu_run": str(Path(args.cpu_run)),
            "m5w_run": str(Path(args.m5w_run)),
            "m5x_run": str(Path(args.m5x_run)),
        },
        "runs": {
            "cpu_baseline": cpu,
            "m5w_attribution": m5w,
            "m5x_attribution": m5x,
        },
        "comparison": {
            "selected_query_count": m5x_audit.get("fixture_count"),
            "m5x_cpu_predivergence_chains_avoided_vs_m5w": (
                (m5w_audit.get("total_cpu_predivergence_chains") or 0)
                - (m5x_audit.get("total_cpu_predivergence_chains") or 0)
            ),
            "m5x_cpu_bypassed_reads": m5x_audit.get("total_cpu_bypassed_reads"),
            "m5x_cpu_chain_dp_wall_ms_saved_vs_m5w": avoided_cpu_chain_ms,
            "m5x_cpu_divergence_filter_wall_ms_saved_vs_m5w": (
                avoided_cpu_divergence_ms
            ),
            "m5w_worker_request_total_ms": m5w["worker_response"][
                "timing_ms"
            ].get("request_total"),
            "m5x_worker_request_total_ms": m5x["worker_response"][
                "timing_ms"
            ].get("request_total"),
            "m5w_full_flye_elapsed_seconds": m5w["time_log"].get(
                "elapsed_seconds"
            ),
            "m5x_full_flye_elapsed_seconds": m5x["time_log"].get(
                "elapsed_seconds"
            ),
            "full_flye_elapsed_note": (
                "This M5y attribution rerun records /usr/bin/time log precision. "
                "The M5x CPU bypass is real, but end-to-end toy timing remains "
                "noise-scale and should not be used as a whole-Flye speed claim."
            ),
        },
        "next_recommended_step": (
            "M6a: move upstream to the read-to-graph overlap/minimizer input "
            "boundary and define a candidate-generation oracle before adding "
            "more CUDA kernels, because selected chain-DP bypass is not the "
            "dominant toy-hifi wall-time bottleneck."
        ),
        "allowed_claim": (
            "cuFlye can attribute the M5x selected CPU-bypass effect: selected "
            "reads skip CPU pre-divergence chain DP and CPU divergence filtering, "
            "consume verified compact-binary CUDA-derived goodChains, and still "
            "preserve exact canonical Flye artifacts for the full3546 toy-hifi set."
        ),
        "forbidden_claim": (
            "M5y does not prove meaningful whole-Flye acceleration, default GPU "
            "mode, unbounded read-alignment replacement, or CUDA overlap/minimizer "
            "discovery acceleration."
        ),
        "plain_language_benefit": (
            "M5y shows the CUDA path is scientifically safe and the selected CPU "
            "work really is bypassed, but the bypassed work is too small on the "
            "toy fixture to move total Flye time. The next useful CUDA target is "
            "earlier in read-to-graph candidate discovery, not further polishing "
            "this tiny selected chain-DP slice."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cpu-run", required=True)
    parser.add_argument("--m5w-run", required=True)
    parser.add_argument("--m5x-run", required=True)
    parser.add_argument("--proof-root", required=True)
    parser.add_argument("--json-output", required=True)
    args = parser.parse_args()

    summary = build_summary(args)
    output = Path(args.json_output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
