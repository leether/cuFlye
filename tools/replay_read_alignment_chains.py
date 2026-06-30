#!/usr/bin/env python3
"""Replay a bounded cuFlye read-alignment fixture."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

from validate_read_alignment_dump import canonical_text, validate


@dataclass(frozen=True)
class EdgeOverlap:
    candidate_id: int
    read_id: int
    read_begin: int
    read_end: int
    read_len: int
    edge_id: int
    edge_left_node: int
    edge_right_node: int
    edge_seq_id: int
    edge_begin: int
    edge_end: int
    edge_len: int
    score: int
    seq_divergence: float


@dataclass
class Chain:
    indices: list[int]
    score: int


def parse_edge_overlaps(path: Path) -> list[EdgeOverlap]:
    records: list[EdgeOverlap] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 14:
                raise ValueError(f"{path}:{line_no}: expected 14 fields, got {len(fields)}")
            ints = [int(value) for value in fields[:13]]
            records.append(EdgeOverlap(*ints, float(fields[13])))
    return records


def parse_chain_divergence(path: Path) -> list[tuple[float, bool]]:
    rows: list[tuple[float, bool]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 3:
                raise ValueError(f"{path}:{line_no}: expected 3 fields, got {len(fields)}")
            chain_id = int(fields[0])
            if chain_id != len(rows):
                raise ValueError(f"{path}:{line_no}: non-contiguous chain id {chain_id}")
            rows.append((float(fields[1]), bool(int(fields[2]))))
    return rows


def chain_read_alignments(overlaps: list[EdgeOverlap], params: dict) -> list[Chain]:
    max_jump = int(params["maximum_jump"])
    max_read_overlap = int(params["max_read_overlap"])
    min_overlap = int(params["minimum_overlap"])
    max_sep = int(params["max_separation"])

    active: list[Chain] = []
    frozen: list[Chain] = []
    for index, edge_alignment in enumerate(overlaps):
        max_score = 0
        max_chain: Chain | None = None
        num_outdated = 0

        can_extend = edge_alignment.edge_begin < max_jump
        can_be_extended = edge_alignment.edge_len - edge_alignment.edge_end < max_jump

        if can_extend:
            for chain in active:
                prev = overlaps[chain.indices[-1]]
                read_diff = edge_alignment.read_begin - prev.read_end
                graph_left_diff = edge_alignment.edge_begin
                graph_right_diff = prev.edge_len - prev.edge_end
                connected = prev.edge_right_node == edge_alignment.edge_left_node
                if (connected and max_jump > read_diff > -max_read_overlap and
                        graph_left_diff + graph_right_diff < max_jump):
                    jump_div = abs(read_diff - (graph_left_diff + graph_right_diff))
                    gap_cost = jump_div // 50 if jump_div > 100 else 0
                    score = chain.score + edge_alignment.score - gap_cost
                    if score > max_score:
                        max_score = score
                        max_chain = chain
                if read_diff > max_jump:
                    num_outdated += 1

        if max_chain is not None:
            active.append(Chain(max_chain.indices + [index], max_score))
        elif can_be_extended:
            active.append(Chain([index], edge_alignment.score))
        else:
            frozen.append(Chain([index], edge_alignment.score))

        if num_outdated > len(active) // 2:
            new_active: list[Chain] = []
            for chain in active:
                prev = overlaps[chain.indices[-1]]
                outdated = edge_alignment.read_begin - prev.read_end > max_jump
                if outdated:
                    frozen.append(chain)
                else:
                    new_active.append(chain)
            active = new_active

    active.extend(frozen)
    active.sort(key=lambda chain: -chain.score)

    accepted: list[Chain] = []
    for chain in active:
        first = overlaps[chain.indices[0]]
        last = overlaps[chain.indices[-1]]
        aln_len = last.read_end - first.read_begin
        if aln_len < min_overlap:
            continue

        chain_overlaps_existing = False
        for existing in accepted:
            existing_first = overlaps[existing.indices[0]]
            existing_last = overlaps[existing.indices[-1]]
            overlap_rate = min(last.read_end, existing_last.read_end) - max(
                first.read_begin, existing_first.read_begin
            )
            if overlap_rate > max_sep:
                chain_overlaps_existing = True
                break
        if not chain_overlaps_existing:
            accepted.append(chain)
    return accepted


def write_read_alignment(chains: list[Chain], overlaps: list[EdgeOverlap],
                         accepted_flags: list[bool], output: Path) -> int:
    rows = []
    output_chain_id = 0
    for chain_id, chain in enumerate(chains):
        if not accepted_flags[chain_id]:
            continue
        for segment_id, overlap_index in enumerate(chain.indices):
            item = overlaps[overlap_index]
            rows.append((
                output_chain_id,
                segment_id,
                item.read_id,
                item.read_begin,
                item.read_end,
                item.read_len,
                item.edge_id,
                item.edge_seq_id,
                item.edge_begin,
                item.edge_end,
                item.edge_len,
                item.score,
                item.seq_divergence,
            ))
        output_chain_id += 1
    output.write_text(canonical_text(rows), encoding="utf-8")
    return len(rows)


def replay_fixture(fixture_dir: Path, output: Path, summary_output: Path | None = None) -> dict:
    manifest = json.loads((fixture_dir / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != "cuflye-read-alignment-replay-fixture-v0":
        raise ValueError("unsupported read alignment replay fixture schema")
    overlaps = parse_edge_overlaps(fixture_dir / "edge-overlaps.tsv")
    divergences = parse_chain_divergence(fixture_dir / "chain-divergence.tsv")
    chains = chain_read_alignments(overlaps, manifest)
    if len(chains) != len(divergences):
        raise ValueError(
            f"replayed chain count {len(chains)} differs from fixture divergence count "
            f"{len(divergences)}"
        )
    accepted_flags = [accepted for _, accepted in divergences]
    output.parent.mkdir(parents=True, exist_ok=True)
    output_records = write_read_alignment(chains, overlaps, accepted_flags, output)
    validation = validate(output, compute_canonical_sha256=True)
    summary = {
        "schema": "cuflye-read-alignment-replay-result-v0",
        "fixture_dir": str(fixture_dir.resolve()),
        "output": str(output.resolve()),
        "query_id": manifest["query_id"],
        "input_records": len(overlaps),
        "candidate_chains": len(chains),
        "accepted_chains": sum(accepted_flags),
        "output_records": output_records,
        "validation": validation,
    }
    if summary_output:
        summary_output.parent.mkdir(parents=True, exist_ok=True)
        summary_output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n",
                                  encoding="utf-8")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture_dir", help="Read-alignment replay fixture directory")
    parser.add_argument("--output", required=True, help="Output read-alignment-v1 TSV")
    parser.add_argument("--json-output", help="Write replay summary JSON")
    args = parser.parse_args()

    summary = replay_fixture(
        Path(args.fixture_dir),
        Path(args.output),
        Path(args.json_output) if args.json_output else None,
    )
    print(f"Read alignment replay: {summary['output_records']} records")
    print(f"  candidate chains: {summary['candidate_chains']}")
    print(f"  accepted chains : {summary['accepted_chains']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
