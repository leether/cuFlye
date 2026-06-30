#!/usr/bin/env python3
"""Plan a validation-safe GPU-first overlap query allowlist."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


QUERY_RE = re.compile(r"query_(-?\d+)$")


@dataclass
class QueryStats:
    query_id: int
    observations: int = 0
    supported_observations: int = 0
    unsupported_observations: int = 0
    selected_observations: int = 0
    first_index: int | None = None
    last_index: int | None = None
    total_cpu_overlap_ms: float = 0.0
    later_cpu_overlap_ms: float = 0.0
    max_cpu_overlap_ms: float = 0.0
    decisions: set[str] = field(default_factory=set)

    def observe(self, row: dict[str, Any], index: int) -> None:
        self.observations += 1
        self.first_index = index if self.first_index is None else min(self.first_index, index)
        self.last_index = index if self.last_index is None else max(self.last_index, index)
        self.decisions.add(str(row.get("decision", "")))
        if row.get("selected"):
            self.selected_observations += 1
        if row.get("supported_shape"):
            self.supported_observations += 1
        else:
            self.unsupported_observations += 1

        timing = row.get("timing_ms", {})
        cpu_ms = float(timing.get("cpu_overlap_ms") or 0.0)
        self.total_cpu_overlap_ms += cpu_ms
        self.max_cpu_overlap_ms = max(self.max_cpu_overlap_ms, cpu_ms)
        if self.supported_observations > 1:
            self.later_cpu_overlap_ms += cpu_ms


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rank repeated supported overlap query ids and emit a validation-safe "
            "GPU-first allowlist."
        )
    )
    parser.add_argument("--ledger-jsonl", action="append", required=True,
                        help="Substitution ledger JSONL file. May be repeated.")
    parser.add_argument("--validation-json", action="append", default=[],
                        help="Worker validation JSON. Failed fixtures are rejected.")
    parser.add_argument("--limit", type=int, default=8,
                        help="Maximum selected query ids. Default: 8.")
    parser.add_argument("--min-observations", type=int, default=2,
                        help="Minimum supported observations per query. Default: 2.")
    parser.add_argument("--allow-unvalidated", action="store_true",
                        help="Allow query ids absent from validation JSON files.")
    parser.add_argument("--output", help="Optional JSON output path.")
    return parser.parse_args()


def query_id_from_fixture(fixture: dict[str, Any]) -> int | None:
    for key in ("fixture_name", "fixture_dir"):
        value = fixture.get(key)
        if not value:
            continue
        match = QUERY_RE.search(Path(str(value)).name)
        if match:
            return int(match.group(1))
    return None


def load_validation(paths: list[str]) -> tuple[set[int], dict[int, dict[str, Any]]]:
    passed: set[int] = set()
    rejected: dict[int, dict[str, Any]] = {}
    for raw_path in paths:
        path = Path(raw_path)
        data = json.loads(path.read_text(encoding="utf-8"))
        for fixture in data.get("fixtures", []):
            query_id = query_id_from_fixture(fixture)
            if query_id is None:
                continue
            status = fixture.get("status")
            diff_status = fixture.get("canonical_diff_status")
            if status == "passed" and diff_status == "match":
                if query_id not in rejected:
                    passed.add(query_id)
                continue
            passed.discard(query_id)
            rejected[query_id] = {
                "query_id": query_id,
                "reason": "validation_failed",
                "validation_json": str(path),
                "status": status,
                "canonical_diff_status": diff_status,
                "oracle_records": fixture.get("oracle_records"),
                "worker_records": fixture.get("worker_records"),
                "error": fixture.get("error"),
            }
    return passed, rejected


def load_ledgers(paths: list[str]) -> dict[int, QueryStats]:
    stats: dict[int, QueryStats] = {}
    index = 0
    for raw_path in paths:
        path = Path(raw_path)
        with path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise SystemExit(f"{path}:{line_number}: invalid JSON: {exc}") from exc
                if "query_id" not in row:
                    continue
                query_id = int(row["query_id"])
                stats.setdefault(query_id, QueryStats(query_id)).observe(row, index)
                index += 1
    return stats


def candidate_rows(stats: dict[int, QueryStats],
                   validation_passed: set[int],
                   rejected: dict[int, dict[str, Any]],
                   allow_unvalidated: bool,
                   min_observations: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    validation_available = bool(validation_passed or rejected)
    for query_id, item in stats.items():
        rejection = rejected.get(query_id)
        if rejection is None and validation_available and not allow_unvalidated:
            if query_id not in validation_passed:
                rejection = {
                    "query_id": query_id,
                    "reason": "missing_validation",
                }
        if rejection is None and item.supported_observations < min_observations:
            rejection = {
                "query_id": query_id,
                "reason": "insufficient_supported_observations",
                "supported_observations": item.supported_observations,
                "min_observations": min_observations,
            }
        rows.append({
            "query_id": query_id,
            "observations": item.observations,
            "supported_observations": item.supported_observations,
            "unsupported_observations": item.unsupported_observations,
            "selected_observations": item.selected_observations,
            "first_index": item.first_index,
            "last_index": item.last_index,
            "total_cpu_overlap_ms": item.total_cpu_overlap_ms,
            "later_cpu_overlap_ms": item.later_cpu_overlap_ms,
            "max_cpu_overlap_ms": item.max_cpu_overlap_ms,
            "decisions": sorted(item.decisions),
            "rejected": rejection is not None,
            "rejection": rejection,
        })
    rows.sort(key=lambda row: (
        row["rejected"],
        -row["later_cpu_overlap_ms"],
        -row["supported_observations"],
        row["first_index"] if row["first_index"] is not None else 10**12,
        abs(row["query_id"]),
        row["query_id"],
    ))
    return rows


def main() -> int:
    args = parse_args()
    if args.limit <= 0:
        raise SystemExit("--limit must be positive")
    if args.min_observations <= 0:
        raise SystemExit("--min-observations must be positive")

    validation_passed, rejected = load_validation(args.validation_json)
    stats = load_ledgers(args.ledger_jsonl)
    candidates = candidate_rows(
        stats,
        validation_passed,
        rejected,
        args.allow_unvalidated,
        args.min_observations,
    )
    selected = [row["query_id"] for row in candidates if not row["rejected"]][:args.limit]
    payload = {
        "schema": "cuflye-gpu-first-selection-plan-v0",
        "ledger_jsonl": args.ledger_jsonl,
        "validation_json": args.validation_json,
        "limit": args.limit,
        "min_observations": args.min_observations,
        "allow_unvalidated": args.allow_unvalidated,
        "selected_query_ids": selected,
        "selected_query_ids_csv": ",".join(str(query_id) for query_id in selected),
        "rejected_query_ids": [
            row["rejection"] for row in candidates if row["rejection"] is not None
        ],
        "candidates": candidates,
    }
    output = json.dumps(payload, indent=2, sort_keys=True)
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
