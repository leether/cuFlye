#!/usr/bin/env python3
"""Select deterministic heterogeneous overlap fixtures for M4n shadow proof."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from diff_overlap_dumps import compare as compare_overlap_dumps
from replay_overlap_chains import ReplayError, replay_fixture, write_overlaps
from validate_candidate_dump import parse_record as parse_candidate_record
from validate_candidate_dump import validate as validate_candidate_dump
from validate_overlap_dump import validate as validate_overlap_dump


SHAPE_METRICS = (
    "candidate_records",
    "target_groups",
    "overlap_records",
    "overlap_density",
)


class SelectionError(RuntimeError):
    pass


@dataclass(frozen=True)
class FixtureShape:
    fixture_dir: Path
    fixture_name: str
    query_id: int
    query_length: int
    candidate_records: int
    target_records: int
    target_groups: int
    unique_target_ids: int
    filtered_positions: int
    overlap_records: int
    overlap_density: float
    candidates_per_target_group: float
    candidate_canonical_sha256: str
    oracle_canonical_sha256: str

    def metric(self, name: str) -> float:
        value = getattr(self, name)
        return float(value)

    def to_json(self) -> dict:
        return {
            "fixture_dir": str(self.fixture_dir.resolve()),
            "fixture_name": self.fixture_name,
            "query_id": self.query_id,
            "query_length": self.query_length,
            "candidate_records": self.candidate_records,
            "target_records": self.target_records,
            "target_groups": self.target_groups,
            "unique_target_ids": self.unique_target_ids,
            "filtered_positions": self.filtered_positions,
            "overlap_records": self.overlap_records,
            "overlap_density": self.overlap_density,
            "candidates_per_target_group": self.candidates_per_target_group,
            "candidate_canonical_sha256": self.candidate_canonical_sha256,
            "oracle_canonical_sha256": self.oracle_canonical_sha256,
        }


@dataclass
class EligibleFixture:
    shape: FixtureShape
    replay_output: Path
    replay_summary: dict
    diff_summary: dict
    selection_reason: str = ""

    def to_json(self) -> dict:
        payload = self.shape.to_json()
        payload.update(
            {
                "selection_reason": self.selection_reason,
                "replay_output": str(self.replay_output.resolve()),
                "replay_status": self.replay_summary.get("status"),
                "diff_status": self.diff_summary.get("status"),
                "diff_left_sha256": self.diff_summary.get("left_sha256"),
                "diff_right_sha256": self.diff_summary.get("right_sha256"),
            }
        )
        return payload


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_nonempty_lines(path: Path) -> list[str]:
    if not path.is_file():
        raise SelectionError(f"missing required file: {path}")
    return [line for line in path.read_text(encoding="utf-8").splitlines() if line]


def unsupported_reasons(manifest: dict) -> list[str]:
    reasons: list[str] = []
    if manifest.get("schema") != "cuflye-overlap-replay-fixture-v0":
        reasons.append(f"schema={manifest.get('schema')!r}")
        return reasons

    params = manifest.get("parameters", {})
    if params.get("nucl_alignment"):
        reasons.append("nucl_alignment=true requires base-alignment replay")
    if params.get("partition_bad_mappings"):
        reasons.append("partition_bad_mappings=true requires trim replay")
    if params.get("keep_alignment"):
        reasons.append("keep_alignment=true is outside packed worker scope")
    if not params.get("only_max_ext"):
        reasons.append("only_max_ext=false is outside packed worker scope")
    if params.get("max_overlaps") != 0:
        reasons.append("max_overlaps!=0 is outside packed worker scope")
    return reasons


def count_filtered_positions(path: Path) -> int:
    return len(read_nonempty_lines(path))


def count_target_records(path: Path) -> int:
    return len(read_nonempty_lines(path))


def candidate_group_summary(path: Path, expected_query_id: int) -> dict:
    validation = validate_candidate_dump(path, compute_canonical_sha256=True)
    target_groups = 0
    seen_completed: set[int] = set()
    current_target: int | None = None
    unique_target_ids: set[int] = set()
    non_contiguous_target_groups: list[int] = []

    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            query_id, _query_pos, _kmer, target_id, _target_pos, _strand = (
                parse_candidate_record(line, line_no, path)
            )
            if query_id != expected_query_id:
                raise SelectionError(
                    f"{path}:{line_no}: query_id {query_id} does not match "
                    f"manifest query_id {expected_query_id}"
                )
            if current_target != target_id:
                if current_target is not None:
                    seen_completed.add(current_target)
                if target_id in seen_completed:
                    non_contiguous_target_groups.append(target_id)
                current_target = target_id
                target_groups += 1
            unique_target_ids.add(target_id)

    if non_contiguous_target_groups:
        preview = ",".join(str(item) for item in non_contiguous_target_groups[:5])
        raise SelectionError(f"{path}: non-contiguous target group(s): {preview}")

    return {
        "candidate_records": validation["records"],
        "candidate_canonical_sha256": validation["canonical_sha256"],
        "target_groups": target_groups,
        "unique_target_ids": len(unique_target_ids),
    }


def fixture_shape(fixture_dir: Path, manifest: dict) -> FixtureShape:
    files = manifest.get("files", {})
    query_id = int(manifest["query_id"])
    candidates_path = fixture_dir / files["candidates"]
    targets_path = fixture_dir / files["targets"]
    filtered_positions_path = fixture_dir / files["filtered_positions"]
    oracle_path = fixture_dir / "oracle.overlaps.tsv"

    candidate_summary = candidate_group_summary(candidates_path, query_id)
    oracle_summary = validate_overlap_dump(oracle_path, compute_canonical_sha256=True)
    candidate_records = int(candidate_summary["candidate_records"])
    target_groups = int(candidate_summary["target_groups"])
    overlap_records = int(oracle_summary["records"])
    overlap_density = overlap_records / candidate_records if candidate_records else 0.0
    candidates_per_target_group = (
        candidate_records / target_groups if target_groups else math.inf
    )

    return FixtureShape(
        fixture_dir=fixture_dir,
        fixture_name=fixture_dir.name,
        query_id=query_id,
        query_length=int(manifest["query_length"]),
        candidate_records=candidate_records,
        target_records=count_target_records(targets_path),
        target_groups=target_groups,
        unique_target_ids=int(candidate_summary["unique_target_ids"]),
        filtered_positions=count_filtered_positions(filtered_positions_path),
        overlap_records=overlap_records,
        overlap_density=overlap_density,
        candidates_per_target_group=candidates_per_target_group,
        candidate_canonical_sha256=str(candidate_summary["candidate_canonical_sha256"]),
        oracle_canonical_sha256=str(oracle_summary["canonical_sha256"]),
    )


def discover_fixture_manifests(root: Path) -> list[tuple[Path, dict]]:
    fixtures: list[tuple[Path, dict]] = []
    for manifest_path in sorted(root.glob("query_*/manifest.json")):
        try:
            manifest = load_json(manifest_path)
        except json.JSONDecodeError as exc:
            raise SelectionError(f"invalid JSON manifest: {manifest_path}: {exc}") from exc
        fixtures.append((manifest_path.parent, manifest))
    if not fixtures:
        raise SelectionError(f"no query_*/manifest.json fixtures found under {root}")
    return fixtures


def assess_fixtures(root: Path, out_dir: Path) -> tuple[list[EligibleFixture], list[dict]]:
    eligible: list[EligibleFixture] = []
    excluded: list[dict] = []
    replay_dir = out_dir / "replay-checks"

    for fixture_dir, manifest in discover_fixture_manifests(root):
        base = {
            "fixture_dir": str(fixture_dir.resolve()),
            "fixture_name": fixture_dir.name,
            "query_id": manifest.get("query_id"),
        }
        reasons = unsupported_reasons(manifest)
        if reasons:
            excluded.append({**base, "status": "unsupported_shape", "reasons": reasons})
            continue

        try:
            shape = fixture_shape(fixture_dir, manifest)
        except Exception as exc:
            excluded.append({**base, "status": "shape_error", "reasons": [str(exc)]})
            continue

        fixture_replay_dir = replay_dir / fixture_dir.name
        replay_output = fixture_replay_dir / "replayed.overlaps.tsv"
        replay_json = fixture_replay_dir / "replay.json"
        try:
            overlaps, replay_summary = replay_fixture(fixture_dir)
            write_overlaps(overlaps, replay_output)
            replay_summary["output"] = str(replay_output.resolve())
            write_json(replay_json, replay_summary)
            diff_summary = compare_overlap_dumps(fixture_dir / "oracle.overlaps.tsv", replay_output)
        except (ReplayError, SelectionError, OSError, ValueError) as exc:
            excluded.append(
                {
                    **base,
                    "status": "replay_failed",
                    "reasons": [str(exc)],
                    "shape": shape.to_json(),
                }
            )
            continue

        if diff_summary.get("status") != "match":
            excluded.append(
                {
                    **base,
                    "status": "replay_mismatch",
                    "reasons": ["CPU replay does not match fixture oracle"],
                    "shape": shape.to_json(),
                    "diff": diff_summary,
                    "replay_output": str(replay_output.resolve()),
                }
            )
            continue

        eligible.append(
            EligibleFixture(
                shape=shape,
                replay_output=replay_output,
                replay_summary=replay_summary,
                diff_summary=diff_summary,
            )
        )

    eligible.sort(key=lambda item: (item.shape.query_id, item.shape.fixture_name))
    return eligible, excluded


def sort_by_metric(items: list[EligibleFixture], metric: str, reverse: bool) -> list[EligibleFixture]:
    return sorted(
        items,
        key=lambda item: (item.shape.metric(metric), item.shape.query_id, item.shape.fixture_name),
        reverse=reverse,
    )


def median_item(items: list[EligibleFixture], metric: str) -> EligibleFixture:
    ordered = sort_by_metric(items, metric, reverse=False)
    return ordered[len(ordered) // 2]


def metric_ranges(items: list[EligibleFixture]) -> dict[str, tuple[float, float]]:
    ranges: dict[str, tuple[float, float]] = {}
    for metric in SHAPE_METRICS:
        values = [item.shape.metric(metric) for item in items]
        ranges[metric] = (min(values), max(values))
    return ranges


def normalized_metric(item: EligibleFixture, metric: str, ranges: dict[str, tuple[float, float]]) -> float:
    lower, upper = ranges[metric]
    if upper == lower:
        return 0.0
    return (item.shape.metric(metric) - lower) / (upper - lower)


def fixture_distance(
    left: EligibleFixture,
    right: EligibleFixture,
    ranges: dict[str, tuple[float, float]],
) -> float:
    return sum(
        (
            normalized_metric(left, metric, ranges)
            - normalized_metric(right, metric, ranges)
        )
        ** 2
        for metric in SHAPE_METRICS
    )


def select_matrix(
    eligible: list[EligibleFixture],
    max_selected: int,
    min_selected: int,
) -> list[EligibleFixture]:
    if max_selected <= 0:
        raise SelectionError("--max-selected must be positive")
    if min_selected <= 0:
        raise SelectionError("--min-selected must be positive")
    if min_selected > max_selected:
        raise SelectionError("--min-selected must be <= --max-selected")
    if len(eligible) < min_selected:
        raise SelectionError(
            f"only {len(eligible)} replay-match fixtures available; need at least {min_selected}"
        )

    selected: list[EligibleFixture] = []
    selected_names: set[str] = set()

    def add(item: EligibleFixture, reason: str) -> None:
        if len(selected) >= max_selected:
            return
        if item.shape.fixture_name in selected_names:
            return
        item.selection_reason = reason
        selected.append(item)
        selected_names.add(item.shape.fixture_name)

    for metric in ("candidate_records", "target_groups", "overlap_records", "overlap_density"):
        add(sort_by_metric(eligible, metric, reverse=False)[0], f"{metric}_min")
        add(sort_by_metric(eligible, metric, reverse=True)[0], f"{metric}_max")
        add(median_item(eligible, metric), f"{metric}_median")

    ranges = metric_ranges(eligible)
    greedy_index = 1
    while len(selected) < max_selected:
        remaining = [
            item for item in eligible if item.shape.fixture_name not in selected_names
        ]
        if not remaining:
            break
        best = max(
            remaining,
            key=lambda item: (
                min(fixture_distance(item, existing, ranges) for existing in selected),
                item.shape.candidate_records,
                item.shape.target_groups,
                item.shape.overlap_records,
                -abs(item.shape.query_id),
                item.shape.query_id,
            ),
        )
        add(best, f"greedy_shape_diversity_{greedy_index:02d}")
        greedy_index += 1

    if len(selected) < min_selected:
        raise SelectionError(
            f"selected {len(selected)} fixtures; need at least {min_selected}"
        )
    return selected


def exclusion_summary(excluded: list[dict]) -> dict:
    status_counts = Counter(item["status"] for item in excluded)
    reason_counts: Counter[str] = Counter()
    for item in excluded:
        for reason in item.get("reasons", []):
            reason_counts[reason] += 1
    return {
        "status_counts": dict(sorted(status_counts.items())),
        "reason_counts": dict(sorted(reason_counts.items())),
    }


def write_selection_files(
    out_dir: Path,
    selected: list[EligibleFixture],
    query_ids_output: Path | None,
    fixtures_output: Path | None,
) -> tuple[Path, Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    query_ids_path = query_ids_output or out_dir / "selected-query-ids.csv"
    fixtures_path = fixtures_output or out_dir / "selected-fixtures.txt"
    query_ids_csv = ",".join(str(item.shape.query_id) for item in selected)
    query_ids_path.parent.mkdir(parents=True, exist_ok=True)
    query_ids_path.write_text(query_ids_csv + "\n", encoding="utf-8")
    fixtures_path.parent.mkdir(parents=True, exist_ok=True)
    fixtures_path.write_text(
        "".join(f"{item.shape.fixture_dir.resolve()}\n" for item in selected),
        encoding="utf-8",
    )
    return query_ids_path, fixtures_path


def build_payload(
    *,
    fixture_root: Path,
    out_dir: Path,
    eligible: list[EligibleFixture],
    excluded: list[dict],
    selected: list[EligibleFixture],
    query_ids_path: Path,
    fixtures_path: Path,
    max_selected: int,
    min_selected: int,
) -> dict:
    selected_query_ids = [item.shape.query_id for item in selected]
    return {
        "schema": "cuflye-overlap-shadow-matrix-selection-v0",
        "status": "ok",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "fixture_root": str(fixture_root.resolve()),
        "out_dir": str(out_dir.resolve()),
        "selection_rule": {
            "name": "shape-extremes-median-greedy-v0",
            "shape_metrics": list(SHAPE_METRICS),
            "max_selected": max_selected,
            "min_selected": min_selected,
            "description": (
                "Filter to packed-worker-supported fixtures whose Python replay "
                "canonical-diffs match the disk oracle, pick min/max/median fixtures "
                "across shape metrics, then greedily maximize normalized metric "
                "distance until the matrix is full."
            ),
        },
        "summary": {
            "discovered_fixtures": len(eligible) + len(excluded),
            "eligible_replay_match_fixtures": len(eligible),
            "excluded_fixtures": len(excluded),
            "selected_fixtures": len(selected),
            "exclusions": exclusion_summary(excluded),
        },
        "selected_query_ids": selected_query_ids,
        "selected_query_ids_csv": ",".join(str(query_id) for query_id in selected_query_ids),
        "selected_query_ids_file": str(query_ids_path.resolve()),
        "selected_fixtures_file": str(fixtures_path.resolve()),
        "selected_fixtures": [item.to_json() for item in selected],
        "eligible_fixtures": [item.to_json() for item in eligible],
        "excluded_fixtures": excluded,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture_root", type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--query-ids-output", type=Path)
    parser.add_argument("--fixtures-output", type=Path)
    parser.add_argument("--max-selected", type=int, default=12)
    parser.add_argument("--min-selected", type=int, default=10)
    args = parser.parse_args()

    fixture_root = args.fixture_root.resolve()
    out_dir = args.out_dir.resolve()
    json_output = (args.json_output or out_dir / "selection.json").resolve()

    eligible, excluded = assess_fixtures(fixture_root, out_dir)
    selected = select_matrix(eligible, args.max_selected, args.min_selected)
    query_ids_path, fixtures_path = write_selection_files(
        out_dir,
        selected,
        args.query_ids_output.resolve() if args.query_ids_output else None,
        args.fixtures_output.resolve() if args.fixtures_output else None,
    )
    payload = build_payload(
        fixture_root=fixture_root,
        out_dir=out_dir,
        eligible=eligible,
        excluded=excluded,
        selected=selected,
        query_ids_path=query_ids_path,
        fixtures_path=fixtures_path,
        max_selected=args.max_selected,
        min_selected=args.min_selected,
    )
    write_json(json_output, payload)

    print("Overlap shadow matrix selection: ok")
    print(f"  discovered: {payload['summary']['discovered_fixtures']}")
    print(f"  eligible  : {payload['summary']['eligible_replay_match_fixtures']}")
    print(f"  selected  : {payload['summary']['selected_fixtures']}")
    print(f"  query ids : {payload['selected_query_ids_csv']}")
    print(f"  manifest  : {json_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
