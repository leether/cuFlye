#!/usr/bin/env python3
"""Benchmark supported overlap replay fixtures as a deterministic batch."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


SUPPORTED_MODES = ("cpu", "cuda-serial", "cuda-parallel")


def run_json(cmd: list[str]) -> None:
    subprocess.check_call(cmd)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def is_supported(manifest: dict) -> bool:
    params = manifest.get("parameters", {})
    return (
        not params.get("nucl_alignment")
        and not params.get("partition_bad_mappings")
        and not params.get("keep_alignment")
        and params.get("only_max_ext")
        and params.get("max_overlaps") == 0
    )


def discover_fixtures(root: Path) -> list[tuple[Path, dict]]:
    fixtures: list[tuple[Path, dict]] = []
    for manifest_path in sorted(root.glob("query_*/manifest.json")):
        manifest = load_json(manifest_path)
        if manifest.get("schema") != "cuflye-overlap-replay-fixture-v0":
            continue
        if is_supported(manifest):
            fixtures.append((manifest_path.parent, manifest))
    fixtures.sort(
        key=lambda item: (
            -int(item[1].get("candidate_records", 0)),
            int(item[1].get("query_id", 0)),
        )
    )
    return fixtures


def run_mode(
    runner_bin: Path,
    fixture_dir: Path,
    out_dir: Path,
    mode: str,
    device: int,
    warmup_runs: int,
    benchmark_runs: int,
) -> dict:
    mode_dir = out_dir / mode
    mode_dir.mkdir(parents=True, exist_ok=True)
    output_tsv = mode_dir / "overlaps.tsv"
    output_json = mode_dir / "run.json"
    cmd = [
        str(runner_bin),
        "--fixture-dir",
        str(fixture_dir),
        "--output-tsv",
        str(output_tsv),
        "--json-output",
        str(output_json),
        "--warmup-runs",
        str(warmup_runs),
        "--benchmark-runs",
        str(benchmark_runs),
    ]
    if mode == "cpu":
        cmd.extend(["--backend", "cpu"])
    elif mode == "cuda-serial":
        cmd.extend(["--backend", "cuda", "--cuda-kernel-mode", "serial", "--device", str(device)])
    elif mode == "cuda-parallel":
        cmd.extend(
            [
                "--backend",
                "cuda",
                "--cuda-kernel-mode",
                "parallel-reduce",
                "--device",
                str(device),
            ]
        )
    else:
        raise ValueError(f"unsupported mode: {mode}")
    subprocess.check_call(cmd)
    return {
        "output_tsv": str(output_tsv),
        "run_json": str(output_json),
        "run": load_json(output_json),
    }


def validate_and_diff(repo_root: Path, fixture_dir: Path, output_tsv: Path, out_dir: Path) -> dict:
    validation_json = out_dir / "validation.json"
    diff_json = out_dir / "oracle.diff.json"
    run_json(
        [
            sys.executable,
            str(repo_root / "tools" / "validate_overlap_dump.py"),
            str(output_tsv),
            "--compute-canonical-sha256",
            "--json-output",
            str(validation_json),
        ]
    )
    run_json(
        [
            sys.executable,
            str(repo_root / "tools" / "diff_overlap_dumps.py"),
            str(fixture_dir / "oracle.overlaps.tsv"),
            str(output_tsv),
            "--json-output",
            str(diff_json),
        ]
    )
    return {
        "validation": load_json(validation_json),
        "diff": load_json(diff_json),
    }


def summarize(results: list[dict], modes: list[str]) -> dict:
    by_mode: dict[str, dict] = {}
    for mode in modes:
        runs = [fixture["modes"][mode]["run"] for fixture in results]
        by_mode[mode] = {
            "fixtures": len(runs),
            "total_mean_before_json_ms": sum(
                run["benchmark"]["mean_total_before_json_ms"] for run in runs
            ),
            "total_mean_core_ms": sum(run["benchmark"]["mean_core_ms"] for run in runs),
            "total_output_records": sum(run["output_records"] for run in runs),
            "total_candidate_records": sum(run["candidate_records"] for run in runs),
        }
    if "cpu" in by_mode:
        cpu_total = by_mode["cpu"]["total_mean_before_json_ms"]
        for mode, summary in by_mode.items():
            if mode == "cpu":
                continue
            cuda_total = summary["total_mean_before_json_ms"]
            summary["speedup_vs_cpu"] = cpu_total / cuda_total if cuda_total else None
            summary["slowdown_vs_cpu"] = cuda_total / cpu_total if cpu_total else None
    return by_mode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture_root", type=Path)
    parser.add_argument("--runner-bin", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--device", type=int, default=0)
    parser.add_argument("--warmup-runs", type=int, default=1)
    parser.add_argument("--benchmark-runs", type=int, default=3)
    parser.add_argument(
        "--modes",
        default="cpu,cuda-serial,cuda-parallel",
        help="Comma-separated modes: cpu,cuda-serial,cuda-parallel",
    )
    parser.add_argument("--json-output", required=True, type=Path)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    modes = [mode.strip() for mode in args.modes.split(",") if mode.strip()]
    unknown = [mode for mode in modes if mode not in SUPPORTED_MODES]
    if unknown:
        parser.error(f"unsupported mode(s): {','.join(unknown)}")

    fixtures = discover_fixtures(args.fixture_root)
    if args.limit > 0:
        fixtures = fixtures[: args.limit]
    if not fixtures:
        raise SystemExit(f"no supported fixtures found under {args.fixture_root}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []
    for fixture_dir, manifest in fixtures:
        query_name = fixture_dir.name
        fixture_out = args.out_dir / query_name
        fixture_result = {
            "fixture_dir": str(fixture_dir),
            "query_id": manifest.get("query_id"),
            "candidate_records": manifest.get("candidate_records"),
            "target_records": manifest.get("target_records"),
            "oracle_overlap_records": manifest.get("oracle_overlap_records"),
            "modes": {},
        }
        for mode in modes:
            mode_result = run_mode(
                args.runner_bin,
                fixture_dir,
                fixture_out,
                mode,
                args.device,
                args.warmup_runs,
                args.benchmark_runs,
            )
            check = validate_and_diff(
                repo_root,
                fixture_dir,
                Path(mode_result["output_tsv"]),
                fixture_out / mode,
            )
            mode_result.update(check)
            fixture_result["modes"][mode] = mode_result
        results.append(fixture_result)

    all_match = all(
        mode_result["diff"].get("status") == "match"
        for fixture in results
        for mode_result in fixture["modes"].values()
    )
    payload = {
        "schema": "cuflye-overlap-replay-batch-benchmark-v0",
        "status": "ok" if all_match else "diff-mismatch",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "fixture_root": str(args.fixture_root),
        "runner_bin": str(args.runner_bin),
        "out_dir": str(args.out_dir),
        "modes": modes,
        "warmup_runs": args.warmup_runs,
        "benchmark_runs": args.benchmark_runs,
        "selected_fixtures": len(results),
        "all_diffs_match": all_match,
        "summary_by_mode": summarize(results, modes),
        "fixtures": results,
    }
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Batch overlap replay benchmark: {payload['status']}")
    print(f"  fixtures: {payload['selected_fixtures']}")
    for mode, summary in payload["summary_by_mode"].items():
        line = f"  {mode}: total_mean={summary['total_mean_before_json_ms']:.6f} ms"
        if "speedup_vs_cpu" in summary:
            line += f" speedup_vs_cpu={summary['speedup_vs_cpu']:.6f}x"
        print(line)
    return 0 if all_match else 1


if __name__ == "__main__":
    raise SystemExit(main())
