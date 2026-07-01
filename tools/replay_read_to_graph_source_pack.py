#!/usr/bin/env python3
"""Replay M6d read-to-graph minimizer source packs outside Flye."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any

from validate_read_to_graph_source_pack import validate_pack


REPLAY_SCHEMA = "cuflye-read-to-graph-minimizer-source-replay-v0"
RAW_SCHEMA = "# schema=cuflye-read-to-graph-raw-overlap-v0"
QUERY_SCHEMA = "# schema=cuflye-read-to-graph-source-query-v0"
BUCKET_SCHEMA = "# schema=cuflye-read-to-graph-source-index-bucket-v0"
EDGE_SCHEMA = "# schema=cuflye-read-to-graph-source-edge-sequence-v0"

LARGE_GAP_PENALTY = 2.0
SMALL_GAP_PENALTY = 0.5
GAP_JUMP_THRESHOLD = 100
MAX_JUMP_GAP = 500
MIN_KMER_SURVIVAL_RATE = 0.01
SAMPLE_RATE = 1.0
MAX_DIVERGENCE = 1.0


@dataclass(frozen=True)
class Match:
    cur_pos: int
    ext_pos: int
    ext_id: int
    kmer_repr: int
    source_order: int


@dataclass
class Overlap:
    query_id: int
    cur_begin: int
    cur_end: int
    cur_len: int
    ext_id: int
    ext_begin: int
    ext_end: int
    ext_len: int
    score: int
    seq_divergence: float
    chain_length: int

    def cur_range(self) -> int:
        return self.cur_end - self.cur_begin

    def ext_range(self) -> int:
        return self.ext_end - self.ext_begin

    def contained_by(self, other: "Overlap") -> bool:
        if self.query_id != other.query_id or self.ext_id != other.ext_id:
            return False
        return (
            other.cur_begin <= self.cur_begin
            and self.cur_end <= other.cur_end
            and other.ext_begin <= self.ext_begin
            and self.ext_end <= other.ext_end
        )


def signed_to_internal_id(signed_id: int) -> int:
    if signed_id > 0:
        return 2 * (signed_id - 1)
    return 2 * (-signed_id) - 1


def rc_signed_id(signed_id: int) -> int:
    return -signed_id


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_data_lines(path: Path, expected_schema: str) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != expected_schema:
        raise ValueError(f"{path}: unexpected schema")
    if len(lines) < 2:
        raise ValueError(f"{path}: missing header")
    return lines[2:]


def read_query(query_dir: Path) -> tuple[int, int]:
    rows = read_data_lines(query_dir / "query.tsv", QUERY_SCHEMA)
    if len(rows) != 1:
        raise ValueError(f"{query_dir}: query.tsv must contain one row")
    fields = rows[0].split("\t")
    if len(fields) != 2:
        raise ValueError(f"{query_dir}: invalid query row")
    return int(fields[0]), len(fields[1])


def read_edge_lengths(query_dir: Path) -> dict[int, int]:
    lengths: dict[int, int] = {}
    for line in read_data_lines(query_dir / "edge-sequences.tsv", EDGE_SCHEMA):
        fields = line.split("\t")
        if len(fields) != 3:
            raise ValueError(f"{query_dir}: invalid edge sequence row")
        edge_id = int(fields[0])
        length = int(fields[1])
        if length != len(fields[2]):
            raise ValueError(f"{query_dir}: edge sequence length mismatch")
        lengths[edge_id] = length
    return lengths


def read_bucket_matches(query_dir: Path, query_id: int) -> list[Match]:
    matches: list[Match] = []
    for order, line in enumerate(read_data_lines(query_dir / "index-buckets.tsv", BUCKET_SCHEMA)):
        fields = line.split("\t")
        if len(fields) != 5:
            raise ValueError(f"{query_dir}: invalid index bucket row")
        row_query_id = int(fields[0])
        cur_pos = int(fields[1])
        kmer_repr = int(fields[2])
        ext_id = int(fields[3])
        ext_pos = int(fields[4])
        if row_query_id != query_id:
            raise ValueError(f"{query_dir}: mixed query ids in index bucket")
        if ext_id == query_id and ext_pos == cur_pos:
            continue
        matches.append(Match(cur_pos, ext_pos, ext_id, kmer_repr, order))
    matches.sort(key=lambda item: (signed_to_internal_id(item.ext_id), item.cur_pos))
    return matches


def read_oracle_rows(query_dir: Path) -> list[dict[str, Any]]:
    rows = []
    for line in read_data_lines(query_dir / "raw-overlaps.tsv", RAW_SCHEMA):
        fields = line.split("\t")
        if len(fields) != 16:
            raise ValueError(f"{query_dir}: invalid raw overlap row")
        rows.append(
            {
                "query_id": int(fields[0]),
                "source_order": int(fields[1]),
                "raw_overlap_count": int(fields[2]),
                "chain_input_count": int(fields[3]),
                "read_id": int(fields[4]),
                "read_begin": int(fields[5]),
                "read_end": int(fields[6]),
                "read_len": int(fields[7]),
                "edge_seq_id": int(fields[8]),
                "edge_begin": int(fields[9]),
                "edge_end": int(fields[10]),
                "edge_len": int(fields[11]),
                "edge_id": int(fields[12]),
                "score": int(fields[13]),
                "seq_divergence": float(fields[14]),
                "passes_chain_input_filter": int(fields[15]),
            }
        )
    return rows


def overlap_test(overlap: Overlap, min_overlap: int, force_local: bool) -> bool:
    if overlap.cur_range() < min_overlap or overlap.ext_range() < min_overlap:
        return False

    length_diff = abs(overlap.cur_range() - overlap.ext_range())
    if length_diff > 0.5 * min(overlap.cur_range(), overlap.ext_range()):
        return False

    if overlap.query_id == overlap.ext_id:
        intersect = min(overlap.cur_end, overlap.ext_end) - max(
            overlap.cur_begin, overlap.ext_begin
        )
        if intersect > overlap.cur_range() / 2:
            return False

    if overlap.query_id == rc_signed_id(overlap.ext_id):
        intersect = min(
            overlap.cur_end, overlap.ext_len - overlap.ext_begin
        ) - max(overlap.cur_begin, overlap.ext_len - overlap.ext_end)
        if intersect > overlap.cur_range() / 2:
            return False

    # The read-to-graph aligner constructs this detector with maxOverhang=0,
    # which disables Flye's non-local overhang check.
    _ = force_local
    return True


def replay_group(
    query_id: int,
    query_len: int,
    ext_id: int,
    ext_len: int,
    group: list[Match],
    *,
    kmer_size: int,
    max_jump: int,
    min_overlap: int,
    force_local: bool,
) -> tuple[list[Overlap], dict[str, Any]]:
    unique_matches = 0
    prev_pos = 0
    for match in group:
        if match.cur_pos != prev_pos:
            unique_matches += 1
            prev_pos = match.cur_pos

    group_summary = {
        "ext_id": ext_id,
        "match_records": len(group),
        "unique_query_positions": unique_matches,
        "prefilter_status": "not-run",
        "dp_proposals": 0,
        "primary_overlaps": 0,
        "detected_overlaps": 0,
    }
    if unique_matches < MIN_KMER_SURVIVAL_RATE * min_overlap:
        group_summary["prefilter_status"] = "too-few-unique-matches"
        return [], group_summary

    min_cur = group[0].cur_pos
    max_cur = group[-1].cur_pos
    min_ext = min(match.ext_pos for match in group)
    max_ext = max(match.ext_pos for match in group)
    if max_cur - min_cur < min_overlap or max_ext - min_ext < min_overlap:
        group_summary["prefilter_status"] = "span-too-short"
        return [], group_summary
    group_summary["prefilter_status"] = "passed"

    matches = list(group)
    ext_sorted = ext_len > query_len
    if ext_sorted:
        matches.sort(key=lambda item: item.ext_pos)

    score_table = [0] * len(matches)
    backtrack_table = [-1] * len(matches)
    for i in range(1, len(matches)):
        max_score = 0
        max_id = 0
        cur_next = matches[i].cur_pos
        ext_next = matches[i].ext_pos

        for j in range(i - 1, -1, -1):
            cur_prev = matches[j].cur_pos
            ext_prev = matches[j].ext_pos
            cur_delta = cur_next - cur_prev
            ext_delta = ext_next - ext_prev
            jump_div = abs(cur_delta - ext_delta)
            if (
                0 < cur_delta < max_jump
                and 0 < ext_delta < max_jump
                and jump_div <= MAX_JUMP_GAP
            ):
                match_score = min(cur_delta, ext_delta, kmer_size)
                gap_cost = int(
                    (LARGE_GAP_PENALTY if jump_div > GAP_JUMP_THRESHOLD else SMALL_GAP_PENALTY)
                    * jump_div
                )
                next_score = score_table[j] + match_score - gap_cost
                if next_score > max_score:
                    max_score = next_score
                    max_id = j
                    if jump_div == 0 and cur_delta < kmer_size:
                        break
            if ext_sorted and ext_delta > max_jump:
                break
            if not ext_sorted and cur_delta > max_jump:
                break

        score_table[i] = max(max_score, kmer_size)
        if max_score > kmer_size:
            backtrack_table[i] = max_id

    ext_overlaps: list[Overlap] = []
    ordered_scores = sorted(range(len(backtrack_table)), key=lambda idx: (-score_table[idx], idx))
    for chain_start in ordered_scores:
        if backtrack_table[chain_start] == -1:
            continue
        last_match = chain_start
        first_match = 0
        chain_length = 0
        pos = chain_start
        while pos != -1:
            first_match = pos
            chain_length += 1
            new_pos = backtrack_table[pos]
            backtrack_table[pos] = -1
            pos = new_pos

        overlap = Overlap(
            query_id=query_id,
            cur_begin=matches[first_match].cur_pos,
            ext_begin=matches[first_match].ext_pos,
            cur_len=query_len,
            ext_id=ext_id,
            ext_len=ext_len,
            cur_end=matches[last_match].cur_pos + kmer_size - 1,
            ext_end=matches[last_match].ext_pos + kmer_size - 1,
            score=score_table[last_match] - score_table[first_match] + kmer_size - 1,
            seq_divergence=0.0,
            chain_length=chain_length,
        )
        if overlap_test(overlap, min_overlap, force_local):
            norm_len = max(overlap.cur_range(), overlap.ext_range())
            if norm_len <= 0:
                continue
            match_rate = min(chain_length * SAMPLE_RATE / norm_len, 1.0)
            if match_rate <= 0:
                continue
            overlap.seq_divergence = math.log(1 / match_rate) / kmer_size
            ext_overlaps.append(overlap)

    group_summary["dp_proposals"] = len(ext_overlaps)
    ext_overlaps.sort(key=lambda row: row.score, reverse=True)
    primary: list[Overlap] = []
    for overlap in ext_overlaps:
        contained = any(overlap.contained_by(prim) and prim.score > overlap.score for prim in primary)
        if not contained:
            primary.append(overlap)
    group_summary["primary_overlaps"] = len(primary)

    detected = [overlap for overlap in primary if overlap.seq_divergence < MAX_DIVERGENCE]
    group_summary["detected_overlaps"] = len(detected)
    return detected, group_summary


def replay_query(query_dir: Path) -> dict[str, Any]:
    manifest = json.loads((query_dir / "manifest.json").read_text(encoding="utf-8"))
    query_id, query_len = read_query(query_dir)
    edge_lengths = read_edge_lengths(query_dir)
    matches = read_bucket_matches(query_dir, query_id)
    oracle_rows = read_oracle_rows(query_dir)

    params = manifest["parameters"]
    kmer_size = int(params["kmer_size"])
    max_jump = int(params["maximum_jump"])
    min_overlap = int(params.get("small_alignment_threshold", params["minimum_overlap"]))

    detected: list[Overlap] = []
    groups: list[dict[str, Any]] = []
    idx = 0
    while idx < len(matches):
        ext_id = matches[idx].ext_id
        end = idx + 1
        while end < len(matches) and matches[end].ext_id == ext_id:
            end += 1
        if ext_id not in edge_lengths:
            raise ValueError(f"{query_dir}: missing edge sequence for {ext_id}")
        group_overlaps, group_summary = replay_group(
            query_id,
            query_len,
            ext_id,
            edge_lengths[ext_id],
            matches[idx:end],
            kmer_size=kmer_size,
            max_jump=max_jump,
            min_overlap=min_overlap,
            force_local=False,
        )
        detected.extend(group_overlaps)
        groups.append(group_summary)
        idx = end

    oracle_chain_input_count = oracle_rows[0]["chain_input_count"] if oracle_rows else 0
    replay_rows = [
        overlap_to_row(overlap, order, len(detected), oracle_chain_input_count)
        for order, overlap in enumerate(detected)
    ]
    comparison = compare_rows(oracle_rows, replay_rows)
    return {
        "query_id": query_id,
        "query_sequence_length": query_len,
        "source_match_records": len(matches),
        "source_ext_group_count": len(groups),
        "source_ext_ids": [group["ext_id"] for group in groups],
        "oracle_raw_overlap_records": len(oracle_rows),
        "replay_raw_overlap_records": len(replay_rows),
        "groups": groups,
        "oracle_rows": oracle_rows,
        "replay_rows": replay_rows,
        "comparison": comparison,
    }


def overlap_to_row(overlap: Overlap, order: int, raw_count: int, chain_input_count: int) -> dict[str, Any]:
    return {
        "query_id": overlap.query_id,
        "source_order": order,
        "raw_overlap_count": raw_count,
        "chain_input_count": chain_input_count,
        "read_id": overlap.query_id,
        "read_begin": overlap.cur_begin,
        "read_end": overlap.cur_end,
        "read_len": overlap.cur_len,
        "edge_seq_id": overlap.ext_id,
        "edge_begin": overlap.ext_begin,
        "edge_end": overlap.ext_end,
        "edge_len": overlap.ext_len,
        "edge_id": 0,
        "score": overlap.score,
        "seq_divergence": overlap.seq_divergence,
        "passes_chain_input_filter": 0,
        "chain_length": overlap.chain_length,
    }


def row_key(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row["read_id"],
        row["read_begin"],
        row["read_end"],
        row["read_len"],
        row["edge_seq_id"],
        row["edge_begin"],
        row["edge_end"],
        row["edge_len"],
        row["score"],
    )


def geometry_key(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row["read_id"],
        row["read_begin"],
        row["read_end"],
        row["read_len"],
        row["edge_seq_id"],
        row["edge_begin"],
        row["edge_end"],
        row["edge_len"],
    )


def compare_rows(oracle_rows: list[dict[str, Any]], replay_rows: list[dict[str, Any]]) -> dict[str, Any]:
    oracle_keys = [row_key(row) for row in oracle_rows]
    replay_keys = [row_key(row) for row in replay_rows]
    oracle_set = set(oracle_keys)
    replay_set = set(replay_keys)
    matched = oracle_set & replay_set
    missing = [row for row in oracle_rows if row_key(row) not in replay_set]
    extra = [row for row in replay_rows if row_key(row) not in oracle_set]
    ordered_match = oracle_keys == replay_keys
    oracle_geometry = [geometry_key(row) for row in oracle_rows]
    replay_geometry = [geometry_key(row) for row in replay_rows]
    oracle_geometry_set = set(oracle_geometry)
    replay_geometry_set = set(replay_geometry)
    geometry_matched = oracle_geometry_set & replay_geometry_set
    geometry_missing = [
        row for row in oracle_rows if geometry_key(row) not in replay_geometry_set
    ]
    geometry_extra = [
        row for row in replay_rows if geometry_key(row) not in oracle_geometry_set
    ]
    geometry_ordered_match = oracle_geometry == replay_geometry
    return {
        "status": "match" if ordered_match else "mismatch",
        "ordered_match": ordered_match,
        "matched_rows": len(matched),
        "missing_rows": len(missing),
        "extra_rows": len(extra),
        "missing_examples": missing[:5],
        "extra_examples": extra[:5],
        "geometry_status": "match" if geometry_ordered_match else "mismatch",
        "geometry_ordered_match": geometry_ordered_match,
        "geometry_matched_rows": len(geometry_matched),
        "geometry_missing_rows": len(geometry_missing),
        "geometry_extra_rows": len(geometry_extra),
        "geometry_missing_examples": geometry_missing[:5],
        "geometry_extra_examples": geometry_extra[:5],
    }


def raw_rows_tsv(rows: list[dict[str, Any]]) -> str:
    lines = [
        RAW_SCHEMA,
        (
            "query_id\tsource_order\traw_overlap_count\tchain_input_count\t"
            "read_id\tread_begin\tread_end\tread_len\tedge_seq_id\tedge_begin\t"
            "edge_end\tedge_len\tedge_id\tscore\tseq_divergence\t"
            "passes_chain_input_filter"
        ),
    ]
    for row in rows:
        lines.append(
            "\t".join(
                [
                    str(row["query_id"]),
                    str(row["source_order"]),
                    str(row["raw_overlap_count"]),
                    str(row["chain_input_count"]),
                    str(row["read_id"]),
                    str(row["read_begin"]),
                    str(row["read_end"]),
                    str(row["read_len"]),
                    str(row["edge_seq_id"]),
                    str(row["edge_begin"]),
                    str(row["edge_end"]),
                    str(row["edge_len"]),
                    str(row["edge_id"]),
                    str(row["score"]),
                    f"{row['seq_divergence']:.9g}",
                    str(row["passes_chain_input_filter"]),
                ]
            )
        )
    return "\n".join(lines) + "\n"


def build_missing_semantics(query_summaries: list[dict[str, Any]]) -> list[str]:
    if all(item["comparison"]["status"] == "match" for item in query_summaries):
        return [
            "edge_id mapping and downstream chain-input filtering are validated by existing oracle rows, not recomputed in this replay",
            "C++ std::sort tie ordering is modeled deterministically by replay source order and must stay diff-gated",
        ]
    if all(
        item["comparison"]["geometry_status"] == "match" for item in query_summaries
    ):
        return [
            "M6d source pack captures enough bucket-hit geometry for selected raw-overlap coordinates, but not exact Flye score/divergence values",
            "non-minimizer query k-mer hits from OverlapDetector::IterKmers are not captured in M6d and can change chain score and divergence",
            "edge_id mapping and downstream chain-input filtering are validated by existing oracle rows, not recomputed in this replay",
        ]
    return [
        "M6d source pack captures minimizer bucket hits, but selected queries still diverge from Flye raw-overlap oracle geometry",
        "non-minimizer query k-mer hits from OverlapDetector::IterKmers are not captured in M6d and can change chain coordinates, score, and divergence",
        "C++ std::sort tie ordering must be resolved for equal-key match groups that still diverge",
        "edge_id mapping and downstream chain-input filtering are validated by existing oracle rows, not recomputed in this replay",
    ]


def replay_pack(pack_root: Path, output_dir: Path | None) -> dict[str, Any]:
    validation = validate_pack(pack_root)
    query_dirs = sorted(pack_root.glob("query_*"), key=lambda path: int(path.name.split("_", 1)[1]))
    queries = [replay_query(path) for path in query_dirs]
    all_replay_rows: list[dict[str, Any]] = []
    for query in queries:
        all_replay_rows.extend(query["replay_rows"])
    raw_tsv = raw_rows_tsv(all_replay_rows)
    totals = {
        "source_match_records": sum(item["source_match_records"] for item in queries),
        "source_ext_groups": sum(item["source_ext_group_count"] for item in queries),
        "oracle_raw_overlap_records": sum(item["oracle_raw_overlap_records"] for item in queries),
        "replay_raw_overlap_records": sum(item["replay_raw_overlap_records"] for item in queries),
        "matched_rows": sum(item["comparison"]["matched_rows"] for item in queries),
        "missing_rows": sum(item["comparison"]["missing_rows"] for item in queries),
        "extra_rows": sum(item["comparison"]["extra_rows"] for item in queries),
        "geometry_matched_rows": sum(
            item["comparison"]["geometry_matched_rows"] for item in queries
        ),
        "geometry_missing_rows": sum(
            item["comparison"]["geometry_missing_rows"] for item in queries
        ),
        "geometry_extra_rows": sum(
            item["comparison"]["geometry_extra_rows"] for item in queries
        ),
    }
    exact_match = all(item["comparison"]["status"] == "match" for item in queries)
    geometry_match = all(
        item["comparison"]["geometry_status"] == "match" for item in queries
    )
    status = "match" if exact_match else "gap-ledger"
    missing_semantics = build_missing_semantics(queries)
    summary = {
        "schema": REPLAY_SCHEMA,
        "status": status,
        "exact_match": exact_match,
        "geometry_match": geometry_match,
        "pack_root": str(pack_root.resolve()),
        "pack_validation_sha256": validation["canonical_sha256"],
        "query_count": len(queries),
        "query_ids": [item["query_id"] for item in queries],
        "totals": totals,
        "replay_raw_overlaps_sha256": sha256_text(raw_tsv),
        "reproduced_semantics": [
            "materialize KmerMatch-like records from captured VertexIndex bucket hits",
            "group KmerMatch records by Flye FastaRecord::Id order",
            "run Flye-style gap-aware chain DP for each ext sequence",
            "apply Flye overlapTest for the read-to-graph detector shape",
            "apply primary-overlap containment filtering for onlyMaxExt=false",
            "apply read-to-graph detector divergence gate with maxDivergence=1.0",
        ],
        "remaining_semantics": missing_semantics,
        "queries": [
            {
                key: value
                for key, value in item.items()
                if key not in {"oracle_rows", "replay_rows", "groups"}
            }
            for item in queries
        ],
    }
    if output_dir is not None:
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "replay.raw-overlaps.tsv").write_text(raw_tsv, encoding="utf-8")
        (output_dir / "replay.summary.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (output_dir / "replay.groups.json").write_text(
            json.dumps(
                {
                    "schema": "cuflye-read-to-graph-minimizer-source-replay-groups-v0",
                    "queries": [
                        {
                            "query_id": item["query_id"],
                            "groups": item["groups"],
                        }
                        for item in queries
                    ],
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
    return summary


def print_report(summary: dict[str, Any]) -> None:
    print(f"Read-to-graph minimizer source replay: {summary['status']}")
    print(f"  pack      : {summary['pack_root']}")
    print(f"  queries   : {summary['query_count']}")
    print(f"  query ids : {','.join(str(q) for q in summary['query_ids'])}")
    print(f"  replay sha: {summary['replay_raw_overlaps_sha256']}")
    for name, value in sorted(summary["totals"].items()):
        print(f"  {name}: {value}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack_root", help="M6d source-pack root")
    parser.add_argument("--output-dir", help="Write replay artifacts to this directory")
    parser.add_argument("--json", action="store_true", help="Print JSON summary")
    parser.add_argument("--json-output", help="Write JSON summary")
    args = parser.parse_args(argv)

    try:
        summary = replay_pack(
            Path(args.pack_root), Path(args.output_dir) if args.output_dir else None
        )
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
