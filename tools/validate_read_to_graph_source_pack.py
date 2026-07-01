#!/usr/bin/env python3
"""Validate M6d read-to-graph minimizer source packs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


PACK_SCHEMA = "cuflye-read-to-graph-minimizer-source-pack-v0"
VALIDATION_SCHEMA = "cuflye-read-to-graph-minimizer-source-pack-validation-v0"
REQUIRED_FILES = (
    "manifest.json",
    "query.tsv",
    "query-minimizers.tsv",
    "index-buckets.tsv",
    "edge-sequences.tsv",
    "raw-overlaps.tsv",
    "oracle.chain-input.tsv",
    "missing-semantics.json",
)
OPTIONAL_FILES = (
    "full-query-hits.tsv",
)
SCHEMA_LINES = {
    "query.tsv": "# schema=cuflye-read-to-graph-source-query-v0",
    "query-minimizers.tsv": "# schema=cuflye-read-to-graph-source-minimizer-v0",
    "index-buckets.tsv": "# schema=cuflye-read-to-graph-source-index-bucket-v0",
    "full-query-hits.tsv": "# schema=cuflye-read-to-graph-source-full-query-hit-v0",
    "edge-sequences.tsv": "# schema=cuflye-read-to-graph-source-edge-sequence-v0",
    "raw-overlaps.tsv": "# schema=cuflye-read-to-graph-raw-overlap-v0",
    "oracle.chain-input.tsv": "# schema=cuflye-read-to-graph-chain-input-v0",
}
EXPECTED_MISSING = (
    "KmerMatch grouping and chain DP inside OverlapDetector::getSeqOverlaps",
    "OverlapDetector::overlapTest filtering semantics",
    "optional nucleotide/base alignment refinement",
    "maxOverlaps and onlyMaxExt final selection behavior",
)


class SourcePackValidationError(ValueError):
    pass


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def data_lines(path: Path, expected_schema: str) -> list[str]:
    text = read_text(path)
    lines = text.splitlines()
    if not lines or lines[0] != expected_schema:
        raise SourcePackValidationError(f"{path}: unexpected schema line")
    if len(lines) < 2:
        raise SourcePackValidationError(f"{path}: missing header")
    return lines[2:]


def count_data_lines(path: Path, expected_schema: str) -> int:
    return len(data_lines(path, expected_schema))


def stable_file_hash(path: Path) -> str:
    text = read_text(path)
    if not text.endswith("\n"):
        raise SourcePackValidationError(f"{path}: file must end with LF")
    return sha256_text(text)


def validate_query_dir(query_dir: Path) -> dict[str, Any]:
    for name in REQUIRED_FILES:
        if not (query_dir / name).is_file():
            raise SourcePackValidationError(f"{query_dir}: missing {name}")

    manifest = read_json(query_dir / "manifest.json")
    if manifest.get("schema") != PACK_SCHEMA:
        raise SourcePackValidationError(
            f"{query_dir}: unsupported schema {manifest.get('schema')!r}"
        )
    query_id = int(manifest["query_id"])
    counts = manifest["counts"]

    actual_counts = {
        "query_minimizers": count_data_lines(
            query_dir / "query-minimizers.tsv",
            SCHEMA_LINES["query-minimizers.tsv"],
        ),
        "index_bucket_records": count_data_lines(
            query_dir / "index-buckets.tsv",
            SCHEMA_LINES["index-buckets.tsv"],
        ),
        "edge_sequence_records": count_data_lines(
            query_dir / "edge-sequences.tsv",
            SCHEMA_LINES["edge-sequences.tsv"],
        ),
        "raw_overlap_records": count_data_lines(
            query_dir / "raw-overlaps.tsv",
            SCHEMA_LINES["raw-overlaps.tsv"],
        ),
        "chain_input_records": count_data_lines(
            query_dir / "oracle.chain-input.tsv",
            SCHEMA_LINES["oracle.chain-input.tsv"],
        ),
    }
    if (query_dir / "full-query-hits.tsv").is_file():
        actual_counts["full_query_hit_records"] = count_data_lines(
            query_dir / "full-query-hits.tsv",
            SCHEMA_LINES["full-query-hits.tsv"],
        )
    for name, actual in actual_counts.items():
        expected = int(counts[name])
        if actual != expected:
            raise SourcePackValidationError(
                f"{query_dir}: {name} expected {expected}, got {actual}"
            )
    if actual_counts["query_minimizers"] <= 0:
        raise SourcePackValidationError(f"{query_dir}: query_minimizers is empty")
    if actual_counts["index_bucket_records"] <= 0:
        raise SourcePackValidationError(f"{query_dir}: index_bucket_records is empty")
    if actual_counts["edge_sequence_records"] <= 0:
        raise SourcePackValidationError(f"{query_dir}: edge_sequence_records is empty")

    query_rows = data_lines(query_dir / "query.tsv", SCHEMA_LINES["query.tsv"])
    if len(query_rows) != 1:
        raise SourcePackValidationError(f"{query_dir}: query.tsv must contain one row")
    query_fields = query_rows[0].split("\t")
    if len(query_fields) != 2 or int(query_fields[0]) != query_id or not query_fields[1]:
        raise SourcePackValidationError(f"{query_dir}: invalid query row")

    missing = read_json(query_dir / "missing-semantics.json")
    if missing.get("status") != "missing-semantics-ledger":
        raise SourcePackValidationError(f"{query_dir}: missing semantics status is invalid")
    missing_items = missing.get("missing", [])
    for item in EXPECTED_MISSING:
        if item not in missing_items:
            raise SourcePackValidationError(
                f"{query_dir}: missing-semantics ledger lacks {item!r}"
            )
    if manifest.get("replay_status") != "missing-semantics-ledger":
        raise SourcePackValidationError(f"{query_dir}: replay_status is invalid")

    file_hashes = {
        name: stable_file_hash(query_dir / name)
        for name in REQUIRED_FILES
    }
    for name in OPTIONAL_FILES:
        if (query_dir / name).is_file():
            file_hashes[name] = stable_file_hash(query_dir / name)
    canonical_parts = []
    canonical_files = list(REQUIRED_FILES) + [
        name for name in OPTIONAL_FILES if (query_dir / name).is_file()
    ]
    for name in sorted(canonical_files):
        canonical_parts.append(name)
        canonical_parts.append(read_text(query_dir / name))
    return {
        "query_dir": str(query_dir.resolve()),
        "query_id": query_id,
        "counts": actual_counts,
        "query_sequence_length": len(query_fields[1]),
        "replay_status": manifest["replay_status"],
        "missing_semantics": missing_items,
        "file_sha256": file_hashes,
        "canonical_sha256": sha256_text("\n".join(canonical_parts) + "\n"),
    }


def discover_query_dirs(pack_root: Path) -> list[Path]:
    query_dirs = sorted(path for path in pack_root.glob("query_*") if path.is_dir())
    if not query_dirs:
        raise SourcePackValidationError(f"{pack_root}: no query_* directories found")
    return query_dirs


def validate_pack(pack_root: Path) -> dict[str, Any]:
    queries = [validate_query_dir(path) for path in discover_query_dirs(pack_root)]
    query_ids = [item["query_id"] for item in queries]
    if len(query_ids) != len(set(query_ids)):
        raise SourcePackValidationError(f"{pack_root}: duplicate query ids")
    totals: dict[str, int] = {}
    for item in queries:
        for name, value in item["counts"].items():
            totals[name] = totals.get(name, 0) + int(value)
    canonical_parts = []
    for item in sorted(queries, key=lambda row: row["query_id"]):
        canonical_parts.append(f"query_{item['query_id']}")
        canonical_parts.append(item["canonical_sha256"])
    return {
        "schema": VALIDATION_SCHEMA,
        "status": "ok",
        "pack_root": str(pack_root.resolve()),
        "query_count": len(queries),
        "query_ids": sorted(query_ids),
        "total_counts": totals,
        "replay_status": "missing-semantics-ledger",
        "missing_semantics": list(EXPECTED_MISSING),
        "queries": sorted(queries, key=lambda row: row["query_id"]),
        "canonical_sha256": sha256_text("\n".join(canonical_parts) + "\n"),
    }


def print_report(summary: dict[str, Any]) -> None:
    print(f"Read-to-graph minimizer source pack: {summary['status']}")
    print(f"  pack root : {summary['pack_root']}")
    print(f"  queries   : {summary['query_count']}")
    print(f"  query ids : {','.join(str(q) for q in summary['query_ids'])}")
    print(f"  canonical : {summary['canonical_sha256']}")
    for name, value in sorted(summary["total_counts"].items()):
        print(f"  {name}: {value}")
    print(f"  replay    : {summary['replay_status']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack_root", help="Source-pack root directory")
    parser.add_argument("--json", action="store_true", help="Print JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary")
    args = parser.parse_args(argv)

    try:
        summary = validate_pack(Path(args.pack_root))
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json_output:
        output_path = Path(args.json_output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print_report(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
