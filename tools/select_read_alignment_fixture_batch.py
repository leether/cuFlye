#!/usr/bin/env python3
"""Select deterministic cuFlye read-alignment replay fixture batches."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from validate_read_alignment_dump import validate


SCHEMA = "cuflye-read-alignment-replay-fixture-v0"
REQUIRED_FILES = (
    "manifest.json",
    "read.tsv",
    "edge-sequences.tsv",
    "edge-overlaps.tsv",
    "chain-divergence.tsv",
    "oracle.read-alignment.tsv",
)


@dataclass(frozen=True)
class ReplayShape:
    input_records: int
    chain_divergence_rows: int
    maximum_jump: int
    max_read_overlap: int
    minimum_overlap: int
    max_separation: int
    reads_base_alignment: bool

    def key(self) -> tuple[int, int, int, int, int, int, bool]:
        return (
            self.input_records,
            self.chain_divergence_rows,
            self.maximum_jump,
            self.max_read_overlap,
            self.minimum_overlap,
            self.max_separation,
            self.reads_base_alignment,
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "input_records_per_fixture": self.input_records,
            "chain_divergence_rows": self.chain_divergence_rows,
            "maximum_jump": self.maximum_jump,
            "max_read_overlap": self.max_read_overlap,
            "minimum_overlap": self.minimum_overlap,
            "max_separation": self.max_separation,
            "reads_base_alignment": self.reads_base_alignment,
        }


@dataclass(frozen=True)
class Fixture:
    fixture_dir: Path
    query_id: int
    shape: ReplayShape
    oracle_records: int
    oracle_chains: int
    oracle_sha256: str | None

    def to_json(self) -> dict[str, Any]:
        return {
            "fixture_dir": str(self.fixture_dir.resolve()),
            "query_id": self.query_id,
            "input_records": self.shape.input_records,
            "chain_divergence_rows": self.shape.chain_divergence_rows,
            "oracle_records": self.oracle_records,
            "oracle_chains": self.oracle_chains,
            "oracle_canonical_sha256": self.oracle_sha256,
        }


def count_lines(path: Path) -> int:
    with path.open("r", encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("schema") != SCHEMA:
        raise ValueError(f"{path}: unsupported fixture schema {manifest.get('schema')!r}")
    return manifest


def load_fixture(fixture_dir: Path) -> Fixture:
    for name in REQUIRED_FILES:
        path = fixture_dir / name
        if not path.is_file():
            raise ValueError(f"{fixture_dir}: missing required file {name}")

    manifest = load_manifest(fixture_dir / "manifest.json")
    input_records = int(manifest["alignment_input_records"])
    edge_overlap_rows = count_lines(fixture_dir / "edge-overlaps.tsv")
    if edge_overlap_rows != input_records:
        raise ValueError(
            f"{fixture_dir}: edge-overlaps rows {edge_overlap_rows} differ from "
            f"manifest alignment_input_records {input_records}"
        )
    chain_rows = count_lines(fixture_dir / "chain-divergence.tsv")
    oracle = validate(fixture_dir / "oracle.read-alignment.tsv", compute_canonical_sha256=True)
    shape = ReplayShape(
        input_records=input_records,
        chain_divergence_rows=chain_rows,
        maximum_jump=int(manifest["maximum_jump"]),
        max_read_overlap=int(manifest["max_read_overlap"]),
        minimum_overlap=int(manifest["minimum_overlap"]),
        max_separation=int(manifest["max_separation"]),
        reads_base_alignment=bool(manifest["reads_base_alignment"]),
    )
    return Fixture(
        fixture_dir=fixture_dir,
        query_id=int(manifest["query_id"]),
        shape=shape,
        oracle_records=int(oracle["records"]),
        oracle_chains=int(oracle["chains"]),
        oracle_sha256=oracle.get("canonical_sha256"),
    )


def discover_fixtures(root: Path) -> tuple[list[Fixture], list[dict[str, str]]]:
    fixtures: list[Fixture] = []
    invalid: list[dict[str, str]] = []
    for manifest_path in sorted(root.glob("query_*/manifest.json")):
        try:
            fixtures.append(load_fixture(manifest_path.parent))
        except Exception as exc:
            invalid.append({
                "fixture_dir": str(manifest_path.parent.resolve()),
                "reason": str(exc),
            })
    if not fixtures and not invalid:
        raise ValueError(f"no query_*/manifest.json fixtures found under {root}")
    fixtures.sort(key=lambda item: (item.query_id, item.fixture_dir.name))
    return fixtures, invalid


def select_fixtures(fixtures: list[Fixture], min_input_records: int,
                    max_input_records: int | None,
                    max_fixtures: int | None) -> list[Fixture]:
    selected = [
        fixture for fixture in fixtures
        if fixture.shape.input_records >= min_input_records and (
            max_input_records is None or fixture.shape.input_records <= max_input_records
        )
    ]
    if max_fixtures is not None:
        selected = selected[:max_fixtures]
    if not selected:
        raise ValueError("fixture selection is empty")
    return selected


def summarize_shapes(fixtures: list[Fixture]) -> list[dict[str, Any]]:
    grouped: dict[ReplayShape, list[Fixture]] = {}
    for fixture in fixtures:
        grouped.setdefault(fixture.shape, []).append(fixture)

    summaries = []
    for shape, group in grouped.items():
        query_ids = [fixture.query_id for fixture in sorted(group, key=lambda item: item.query_id)]
        summaries.append({
            **shape.to_json(),
            "fixture_count": len(group),
            "query_ids": query_ids,
            "total_input_records": sum(item.shape.input_records for item in group),
            "total_oracle_records": sum(item.oracle_records for item in group),
        })
    summaries.sort(
        key=lambda item: (
            item["input_records_per_fixture"],
            item["chain_divergence_rows"],
            item["maximum_jump"],
            item["max_read_overlap"],
            item["minimum_overlap"],
            item["max_separation"],
            item["reads_base_alignment"],
        )
    )
    return summaries


def write_fixture_list(path: Path, fixtures: list[Fixture]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(f"{fixture.fixture_dir.resolve()}\n" for fixture in fixtures),
        encoding="utf-8",
    )


def build_summary(root: Path, fixtures: list[Fixture], invalid: list[dict[str, str]],
                  selected: list[Fixture],
                  fixture_list: Path) -> dict[str, Any]:
    excluded = [
        fixture for fixture in fixtures
        if fixture.fixture_dir not in {item.fixture_dir for item in selected}
    ]
    return {
        "schema": "cuflye-read-alignment-fixture-selection-v0",
        "fixture_root": str(root.resolve()),
        "fixture_list": str(fixture_list.resolve()),
        "discovered_fixture_count": len(fixtures) + len(invalid),
        "valid_fixture_count": len(fixtures),
        "invalid_fixture_count": len(invalid),
        "selected_fixture_count": len(selected),
        "excluded_fixture_count": len(excluded),
        "selected_total_input_records": sum(
            fixture.shape.input_records for fixture in selected
        ),
        "selected_total_oracle_records": sum(fixture.oracle_records for fixture in selected),
        "selected_shape_group_count": len({fixture.shape for fixture in selected}),
        "selected_shape_groups": summarize_shapes(selected),
        "invalid_fixtures": invalid,
        "excluded_fixtures": [fixture.to_json() for fixture in excluded],
        "selected_fixtures": [fixture.to_json() for fixture in selected],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-root", required=True,
                        help="Root containing query_*/ read-alignment replay fixtures")
    parser.add_argument("--fixtures-output", required=True,
                        help="Write selected fixture directory list")
    parser.add_argument("--summary-output", required=True,
                        help="Write selection summary JSON")
    parser.add_argument("--min-input-records", type=int, default=1,
                        help="Only select fixtures with at least this many input records")
    parser.add_argument("--max-input-records", type=int,
                        help="Only select fixtures with at most this many input records")
    parser.add_argument("--max-fixtures", type=int,
                        help="Optional cap after deterministic query-id ordering")
    args = parser.parse_args()

    if args.min_input_records < 1:
        parser.error("--min-input-records must be greater than zero")
    if args.max_input_records is not None and args.max_input_records < args.min_input_records:
        parser.error("--max-input-records must be greater than or equal to --min-input-records")
    if args.max_fixtures is not None and args.max_fixtures < 1:
        parser.error("--max-fixtures must be greater than zero")

    root = Path(args.fixture_root)
    fixtures_output = Path(args.fixtures_output)
    summary_output = Path(args.summary_output)
    fixtures, invalid = discover_fixtures(root)
    selected = select_fixtures(
        fixtures, args.min_input_records, args.max_input_records, args.max_fixtures
    )
    write_fixture_list(fixtures_output, selected)
    summary = build_summary(root, fixtures, invalid, selected, fixtures_output)
    summary_output.parent.mkdir(parents=True, exist_ok=True)
    summary_output.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "Selected "
        f"{summary['selected_fixture_count']} of {summary['valid_fixture_count']} valid "
        f"read-alignment fixtures ({summary['discovered_fixture_count']} discovered)"
    )
    print(f"  shape groups: {summary['selected_shape_group_count']}")
    print(f"  total input records: {summary['selected_total_input_records']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
