#!/usr/bin/env python3
"""Benchmark read-alignment pre-divergence CPU/CUDA batch crossover."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from diff_read_alignment_dumps import compare
from select_read_alignment_fixture_batch import Fixture, discover_fixtures, load_fixture


@dataclass(frozen=True)
class WorkerMode:
    name: str
    backend: str
    extra_args: tuple[str, ...]


WORKER_MODES = (
    WorkerMode("cpu", "cpu", ()),
    WorkerMode("cuda-cold", "cuda", ()),
    WorkerMode("cuda-persistent-bulk", "cuda",
               ("--cuda-persistent-arena", "--cuda-persistent-bulk-output")),
)


def parse_batch_sizes(value: str) -> list[int]:
    sizes: list[int] = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        size = int(item)
        if size < 1:
            raise ValueError("batch sizes must be positive")
        sizes.append(size)
    if not sizes:
        raise ValueError("at least one batch size is required")
    return sizes


def load_fixtures(fixture_list: Path | None, fixture_root: Path | None,
                  max_fixtures: int | None) -> list[Fixture]:
    if fixture_list is None and fixture_root is None:
        raise ValueError("either --fixture-list or --fixture-root is required")
    if fixture_list is not None and fixture_root is not None:
        raise ValueError("--fixture-list and --fixture-root are mutually exclusive")

    if fixture_list is not None:
        fixtures = []
        with fixture_list.open("r", encoding="utf-8") as handle:
            for line_no, line in enumerate(handle, 1):
                path = line.strip()
                if not path:
                    continue
                try:
                    fixtures.append(load_fixture(Path(path)))
                except Exception as exc:
                    raise ValueError(f"{fixture_list}:{line_no}: {exc}") from exc
    else:
        assert fixture_root is not None
        fixtures, invalid = discover_fixtures(fixture_root)
        if invalid:
            print(f"Skipping {len(invalid)} invalid fixtures under {fixture_root}")

    fixtures.sort(key=lambda fixture: (fixture.query_id, fixture.fixture_dir.name))
    if max_fixtures is not None:
        fixtures = fixtures[:max_fixtures]
    if not fixtures:
        raise ValueError("fixture selection is empty")
    return fixtures


def write_fixture_list(path: Path, fixtures: list[Fixture]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(f"{fixture.fixture_dir.resolve()}\n" for fixture in fixtures),
        encoding="utf-8",
    )


def run_command(command: list[str], stdout_path: Path, stderr_path: Path) -> dict[str, Any]:
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    end = time.monotonic()
    stdout_path.write_text(result.stdout, encoding="utf-8")
    stderr_path.write_text(result.stderr, encoding="utf-8")
    return {
        "command": command,
        "elapsed_wall_ms": (end - start) * 1000.0,
        "exit_status": result.returncode,
        "stdout": str(stdout_path.resolve()),
        "stderr": str(stderr_path.resolve()),
    }


def worker_output_tsv(output_dir: Path, fixture: Fixture) -> Path:
    return output_dir / fixture.fixture_dir.name / "read-alignment.tsv"


def validate_mode_outputs(cpu_output_dir: Path, mode_output_dir: Path,
                          fixtures: list[Fixture], sample_count: int) -> dict[str, Any]:
    samples: list[dict[str, Any]] = []
    mismatches: list[dict[str, Any]] = []
    matched = 0
    total_records = 0

    for fixture in fixtures:
        left = worker_output_tsv(cpu_output_dir, fixture)
        right = worker_output_tsv(mode_output_dir, fixture)
        summary = compare(left, right, include_diff=False)
        total_records += int(summary["left_records"])
        if summary["status"] == "match":
            matched += 1
        else:
            mismatches.append({
                "query_id": fixture.query_id,
                "left": summary["left"],
                "right": summary["right"],
                "left_sha256": summary["left_sha256"],
                "right_sha256": summary["right_sha256"],
            })
        if len(samples) < sample_count:
            samples.append({
                "query_id": fixture.query_id,
                "records": summary["left_records"],
                "canonical_sha256": summary["left_sha256"],
            })

    return {
        "fixture_count": len(fixtures),
        "matched_fixture_count": matched,
        "mismatched_fixture_count": len(mismatches),
        "all_match": matched == len(fixtures),
        "total_records": total_records,
        "samples": samples,
        "mismatches": mismatches[:sample_count],
        "mismatches_truncated": len(mismatches) > sample_count,
    }


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def timing_value(summary: dict[str, Any], key: str) -> float:
    return float(summary.get("timing_ms", {}).get(key, 0.0))


def benchmark_value(summary: dict[str, Any], key: str) -> float:
    return float(summary.get("benchmark", {}).get(key, 0.0))


def safe_ratio(numerator: float, denominator: float) -> float | None:
    if denominator == 0:
        return None
    return numerator / denominator


def summarize_mode_json(payload: dict[str, Any]) -> dict[str, Any]:
    timing = payload.get("timing_ms", {})
    benchmark = payload.get("benchmark", {})
    return {
        "backend": payload.get("backend"),
        "cuda_execution_mode": payload.get("cuda_execution_mode"),
        "fixture_count": payload.get("fixture_count"),
        "shape_group_count": payload.get("shape_group_count"),
        "total_input_records": payload.get("total_input_records"),
        "output_records": payload.get("output_records"),
        "supported_shape": payload.get("supported_shape"),
        "timing_ms": {
            "setup": timing.get("setup", 0.0),
            "device_allocation": timing.get("device_allocation", 0.0),
            "host_to_device": timing.get("host_to_device", 0.0),
            "one_time_setup": timing.get("one_time_setup", 0.0),
            "one_time_device_allocation": timing.get("one_time_device_allocation", 0.0),
            "one_time_host_to_device": timing.get("one_time_host_to_device", 0.0),
            "one_time_total": timing.get("one_time_total", 0.0),
            "kernel": timing.get("kernel", 0.0),
            "cpu_chain": timing.get("cpu_chain", 0.0),
            "device_to_host": timing.get("device_to_host", 0.0),
            "finalize": timing.get("finalize", 0.0),
            "write_output": timing.get("write_output", 0.0),
            "total_before_json": timing.get("total_before_json", 0.0),
        },
        "benchmark": {
            "warmup_runs": benchmark.get("warmup_runs", 0),
            "timed_runs": benchmark.get("timed_runs", 0),
            "mean_total_before_json_ms": benchmark.get("mean_total_before_json_ms", 0.0),
            "min_total_before_json_ms": benchmark.get("min_total_before_json_ms", 0.0),
            "max_total_before_json_ms": benchmark.get("max_total_before_json_ms", 0.0),
            "mean_core_ms": benchmark.get("mean_core_ms", 0.0),
        },
        "memory": payload.get("memory"),
        "device": payload.get("device"),
    }


def compare_timing(cpu_json: dict[str, Any], cuda_json: dict[str, Any]) -> dict[str, Any]:
    cpu_mean_total = benchmark_value(cpu_json, "mean_total_before_json_ms")
    cuda_mean_total = benchmark_value(cuda_json, "mean_total_before_json_ms")
    cuda_one_time_total = timing_value(cuda_json, "one_time_total")
    timed_runs = float(cuda_json.get("benchmark", {}).get("timed_runs", 1) or 1)
    cuda_amortized = cuda_mean_total + cuda_one_time_total / timed_runs
    cuda_single_invocation = timing_value(cuda_json, "total_before_json") + cuda_one_time_total
    return {
        "cpu_mean_total_before_json_ms": cpu_mean_total,
        "cuda_mean_total_before_json_ms": cuda_mean_total,
        "cuda_one_time_total_ms": cuda_one_time_total,
        "cuda_amortized_total_before_json_ms": cuda_amortized,
        "cuda_single_invocation_total_before_json_ms": cuda_single_invocation,
        "hot_path_speedup_vs_cpu": safe_ratio(cpu_mean_total, cuda_mean_total),
        "amortized_speedup_vs_cpu": safe_ratio(cpu_mean_total, cuda_amortized),
        "single_invocation_speedup_vs_cpu": safe_ratio(cpu_mean_total, cuda_single_invocation),
    }


def run_worker_mode(worker_bin: Path, out_dir: Path, fixture_list: Path,
                    mode: WorkerMode, warmup_runs: int, benchmark_runs: int,
                    device: int, memory_budget_bytes: int | None) -> dict[str, Any]:
    mode_dir = out_dir / mode.name
    output_dir = mode_dir / "read-alignment-output"
    json_output = mode_dir / "worker.json"
    command = [
        str(worker_bin),
        "--backend", mode.backend,
        "--batch-fixtures-file", str(fixture_list),
        "--batch-output-dir", str(output_dir),
        "--batch-json-output", str(json_output),
        "--allow-heterogeneous-batch",
        "--emit-pre-divergence-chains",
        "--warmup-runs", str(warmup_runs),
        "--benchmark-runs", str(benchmark_runs),
    ]
    if mode.backend == "cuda":
        command.extend(["--device", str(device)])
    if memory_budget_bytes is not None and mode.backend == "cuda":
        command.extend(["--memory-budget-bytes", str(memory_budget_bytes)])
    command.extend(mode.extra_args)

    run = run_command(command, mode_dir / "stdout.log", mode_dir / "stderr.log")
    if run["exit_status"] != 0:
        raise RuntimeError(f"{mode.name} worker failed with exit {run['exit_status']}")
    payload = read_json(json_output)
    return {
        "run": run,
        "json": summarize_mode_json(payload),
        "json_path": str(json_output.resolve()),
        "output_dir": str(output_dir.resolve()),
        "raw_json": payload,
    }


def run_batch_case(worker_bin: Path, output_dir: Path, fixtures: list[Fixture],
                   batch_size: int, warmup_runs: int, benchmark_runs: int,
                   device: int, memory_budget_bytes: int | None,
                   sample_count: int) -> dict[str, Any]:
    selected = fixtures[:batch_size]
    case_dir = output_dir / f"batch-{batch_size:06d}"
    fixture_list = case_dir / "fixtures.list"
    write_fixture_list(fixture_list, selected)

    modes: dict[str, dict[str, Any]] = {}
    for mode in WORKER_MODES:
        modes[mode.name] = run_worker_mode(
            worker_bin, case_dir, fixture_list, mode, warmup_runs,
            benchmark_runs, device, memory_budget_bytes,
        )

    cpu_output_dir = Path(modes["cpu"]["output_dir"])
    validation: dict[str, Any] = {}
    for mode in WORKER_MODES:
        if mode.name == "cpu":
            continue
        validation[mode.name] = validate_mode_outputs(
            cpu_output_dir, Path(modes[mode.name]["output_dir"]), selected, sample_count
        )

    cpu_json = modes["cpu"]["raw_json"]
    cold_json = modes["cuda-cold"]["raw_json"]
    bulk_json = modes["cuda-persistent-bulk"]["raw_json"]
    return {
        "batch_size": batch_size,
        "fixture_list": str(fixture_list.resolve()),
        "query_ids": [fixture.query_id for fixture in selected],
        "query_ids_csv": ",".join(str(fixture.query_id) for fixture in selected),
        "shape_group_count": modes["cpu"]["json"]["shape_group_count"],
        "total_input_records": modes["cpu"]["json"]["total_input_records"],
        "output_records": modes["cpu"]["json"]["output_records"],
        "modes": {name: {
            "run": value["run"],
            "json": value["json"],
            "json_path": value["json_path"],
            "output_dir": value["output_dir"],
        } for name, value in modes.items()},
        "validation": validation,
        "timing_comparison": {
            "cuda_cold": compare_timing(cpu_json, cold_json),
            "cuda_persistent_bulk": compare_timing(cpu_json, bulk_json),
        },
    }


def summarize_crossover(cases: list[dict[str, Any]]) -> dict[str, Any]:
    hot_path = None
    amortized = None
    single_invocation = None
    for case in cases:
        comparison = case["timing_comparison"]["cuda_persistent_bulk"]
        if hot_path is None and (comparison["hot_path_speedup_vs_cpu"] or 0.0) > 1.0:
            hot_path = case["batch_size"]
        if amortized is None and (comparison["amortized_speedup_vs_cpu"] or 0.0) > 1.0:
            amortized = case["batch_size"]
        if single_invocation is None and (comparison["single_invocation_speedup_vs_cpu"] or 0.0) > 1.0:
            single_invocation = case["batch_size"]

    largest = cases[-1]
    return {
        "hot_path_crossover_batch_size": hot_path,
        "amortized_crossover_batch_size": amortized,
        "single_invocation_crossover_batch_size": single_invocation,
        "largest_batch_size": largest["batch_size"],
        "largest_batch_timing_comparison": largest["timing_comparison"],
        "all_cuda_outputs_match_cpu": all(
            mode_validation["all_match"]
            for case in cases
            for mode_validation in case["validation"].values()
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker-bin", required=True,
                        help="Path to cuflye-cuda-read-alignment-chain-replay")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--fixture-list", help="Existing fixture list")
    source.add_argument("--fixture-root", help="Root containing query_*/ fixtures")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--summary-output", required=True)
    parser.add_argument("--batch-sizes", default="16,64,256,1024",
                        help="Comma-separated prefix batch sizes. The full fixture count is added.")
    parser.add_argument("--max-fixtures", type=int,
                        help="Cap fixtures after deterministic query-id ordering")
    parser.add_argument("--warmup-runs", type=int, default=0)
    parser.add_argument("--benchmark-runs", type=int, default=1)
    parser.add_argument("--device", type=int, default=0)
    parser.add_argument("--memory-budget-bytes", type=int)
    parser.add_argument("--sample-count", type=int, default=5)
    args = parser.parse_args()

    if args.warmup_runs < 0:
        parser.error("--warmup-runs must be non-negative")
    if args.benchmark_runs < 1:
        parser.error("--benchmark-runs must be at least 1")
    if args.max_fixtures is not None and args.max_fixtures < 1:
        parser.error("--max-fixtures must be positive")
    if args.sample_count < 1:
        parser.error("--sample-count must be positive")

    worker_bin = Path(args.worker_bin)
    if not worker_bin.is_file():
        parser.error(f"worker binary not found: {worker_bin}")
    output_dir = Path(args.output_dir)
    summary_output = Path(args.summary_output)
    output_dir.mkdir(parents=True, exist_ok=True)

    fixtures = load_fixtures(
        Path(args.fixture_list) if args.fixture_list else None,
        Path(args.fixture_root) if args.fixture_root else None,
        args.max_fixtures,
    )
    requested_sizes = parse_batch_sizes(args.batch_sizes)
    effective_sizes = sorted({
        min(size, len(fixtures)) for size in requested_sizes if size <= len(fixtures)
    } | {len(fixtures)})

    cases = []
    for batch_size in effective_sizes:
        print(f"M5q crossover batch size {batch_size}")
        cases.append(run_batch_case(
            worker_bin, output_dir, fixtures, batch_size, args.warmup_runs,
            args.benchmark_runs, args.device, args.memory_budget_bytes,
            args.sample_count,
        ))

    summary = {
        "schema": "cuflye-read-alignment-predivergence-crossover-v0",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "host": {
            "hostname": platform.node(),
            "platform": platform.platform(),
            "machine": platform.machine(),
        },
        "worker_bin": str(worker_bin.resolve()),
        "fixture_source": {
            "fixture_list": str(Path(args.fixture_list).resolve()) if args.fixture_list else None,
            "fixture_root": str(Path(args.fixture_root).resolve()) if args.fixture_root else None,
            "fixture_count": len(fixtures),
            "max_fixtures": args.max_fixtures,
        },
        "settings": {
            "requested_batch_sizes": requested_sizes,
            "effective_batch_sizes": effective_sizes,
            "warmup_runs": args.warmup_runs,
            "benchmark_runs": args.benchmark_runs,
            "device": args.device,
            "memory_budget_bytes": args.memory_budget_bytes,
        },
        "crossover": summarize_crossover(cases),
        "cases": cases,
    }
    summary_output.parent.mkdir(parents=True, exist_ok=True)
    summary_output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n",
                              encoding="utf-8")

    if not summary["crossover"]["all_cuda_outputs_match_cpu"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
