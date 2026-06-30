#!/usr/bin/env python3
"""Replay Flye candidate-to-overlap chaining for a bounded cuFlye fixture."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import math
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

from validate_candidate_dump import parse_record as parse_candidate_record
from validate_candidate_dump import validate as validate_candidate_dump
from validate_overlap_dump import format_float


class ReplayError(RuntimeError):
    pass


@dataclass(frozen=True)
class Candidate:
    query_id: int
    query_pos: int
    kmer: int
    target_id: int
    target_pos: int
    strand: str


@dataclass
class Overlap:
    cur_id: int
    cur_begin: int
    cur_end: int
    cur_len: int
    ext_id: int
    ext_begin: int
    ext_end: int
    ext_len: int
    score: int
    seq_divergence: float

    def cur_range(self) -> int:
        return self.cur_end - self.cur_begin

    def ext_range(self) -> int:
        return self.ext_end - self.ext_begin

    def lr_overhang(self) -> int:
        return max(
            min(self.cur_begin, self.ext_begin),
            min(self.cur_len - self.cur_end, self.ext_len - self.ext_end),
        )

    def contained_by(self, other: "Overlap") -> bool:
        if self.cur_id != other.cur_id or self.ext_id != other.ext_id:
            return False
        return (
            other.cur_begin <= self.cur_begin
            and self.cur_end <= other.cur_end
            and other.ext_begin <= self.ext_begin
            and self.ext_end <= other.ext_end
        )

    def as_tsv(self) -> str:
        return "\t".join(
            [
                str(self.cur_id),
                str(self.cur_begin),
                str(self.cur_end),
                str(self.cur_len),
                str(self.ext_id),
                str(self.ext_begin),
                str(self.ext_end),
                str(self.ext_len),
                str(self.score),
                format_float(self.seq_divergence),
            ]
        )


def f32(value: float) -> float:
    return struct.unpack("f", struct.pack("f", value))[0]


def load_logf():
    candidates = [ctypes.util.find_library("m"), None]
    for candidate in candidates:
        try:
            library = ctypes.CDLL(candidate) if candidate else ctypes.CDLL(None)
            logf = library.logf
        except (OSError, AttributeError):
            continue
        logf.argtypes = [ctypes.c_float]
        logf.restype = ctypes.c_float
        return logf
    return None


LOGF = load_logf()


def cxx_logf(value: float) -> float:
    if LOGF is None:
        return f32(math.log(value))
    return float(LOGF(ctypes.c_float(value)))


def load_manifest(fixture_dir: Path) -> dict:
    manifest_path = fixture_dir / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ReplayError(f"missing manifest: {manifest_path}") from exc
    if manifest.get("schema") != "cuflye-overlap-replay-fixture-v0":
        raise ReplayError(
            f"unsupported fixture schema: {manifest.get('schema')!r}"
        )
    return manifest


def require_supported_shape(manifest: dict) -> None:
    params = manifest.get("parameters", {})
    unsupported = []
    if params.get("nucl_alignment"):
        unsupported.append("nucl_alignment=true requires Flye base-alignment replay")
    if params.get("partition_bad_mappings"):
        unsupported.append("partition_bad_mappings=true requires trim replay")
    if params.get("keep_alignment"):
        unsupported.append("keep_alignment=true is outside M4b replay scope")
    if unsupported:
        raise ReplayError("unsupported overlap replay shape: " + "; ".join(unsupported))


def load_candidates(path: Path, expected_query_id: int) -> list[Candidate]:
    validate_candidate_dump(path, compute_canonical_sha256=False)
    records: list[Candidate] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            record = parse_candidate_record(line, line_no, path)
            candidate = Candidate(*record)
            if candidate.query_id != expected_query_id:
                raise ReplayError(
                    f"{path}:{line_no}: query_id {candidate.query_id} does not match "
                    f"fixture query_id {expected_query_id}"
                )
            records.append(candidate)
    if not records:
        raise ReplayError(f"{path}: candidate fixture is empty")
    return records


def load_filtered_positions(path: Path) -> list[int]:
    positions: list[int] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            text = line.rstrip("\n")
            if not text:
                raise ReplayError(f"{path}:{line_no}: blank filtered position")
            try:
                position = int(text, 10)
            except ValueError as exc:
                raise ReplayError(
                    f"{path}:{line_no}: filtered position must be integer"
                ) from exc
            if position < 0:
                raise ReplayError(f"{path}:{line_no}: filtered position is negative")
            positions.append(position)
    return sorted(positions)


def load_targets(path: Path) -> dict[int, int]:
    targets: dict[int, int] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 2:
                raise ReplayError(f"{path}:{line_no}: expected target_id and length")
            target_id = int(fields[0], 10)
            target_len = int(fields[1], 10)
            if target_id == 0:
                raise ReplayError(f"{path}:{line_no}: target_id must not be zero")
            if target_len <= 0:
                raise ReplayError(f"{path}:{line_no}: target length must be positive")
            targets[target_id] = target_len
    if not targets:
        raise ReplayError(f"{path}: targets fixture is empty")
    return targets


def overlap_test(overlap: Overlap, params: dict) -> bool:
    min_overlap = int(params["minimum_overlap"])
    if overlap.cur_range() < min_overlap or overlap.ext_range() < min_overlap:
        return False

    length_diff = abs(overlap.cur_range() - overlap.ext_range())
    if length_diff > 0.5 * min(overlap.cur_range(), overlap.ext_range()):
        return False

    if overlap.cur_id == overlap.ext_id:
        intersect = min(overlap.cur_end, overlap.ext_end) - max(
            overlap.cur_begin, overlap.ext_begin
        )
        if intersect > overlap.cur_range() / 2:
            return False

    if overlap.cur_id == -overlap.ext_id:
        intersect = min(overlap.cur_end, overlap.ext_len - overlap.ext_begin) - max(
            overlap.cur_begin, overlap.ext_len - overlap.ext_end
        )
        if intersect > overlap.cur_range() / 2:
            return False

    if (
        not params["force_local"]
        and params["check_overhang"]
        and overlap.lr_overhang() > int(params["maximum_overhang"])
    ):
        return False
    return True


def chain_target(
    matches: list[Candidate],
    manifest: dict,
    targets: dict[int, int],
    filtered_positions: list[int],
) -> list[Overlap]:
    params = manifest["parameters"]
    query_id = int(manifest["query_id"])
    cur_len = int(manifest["query_length"])
    kmer_size = int(params["kmer_size"])
    min_overlap = int(params["minimum_overlap"])
    max_jump = int(params["maximum_jump"])
    max_gap = int(params["max_jump_gap"])
    gap_jump_threshold = int(params["chain_gap_jump_threshold"])
    lg_gap = float(params["chain_large_gap_penalty"])
    sm_gap = float(params["chain_small_gap_penalty"])

    unique_matches = 0
    prev_pos = 0
    for match in matches:
        if match.query_pos != prev_pos:
            unique_matches += 1
            prev_pos = match.query_pos
    if unique_matches < float(params["min_kmer_survival_rate"]) * min_overlap:
        return []

    ext_id = matches[0].target_id
    try:
        ext_len = targets[ext_id]
    except KeyError as exc:
        raise ReplayError(f"missing target length for target_id {ext_id}") from exc

    min_cur = matches[0].query_pos
    max_cur = matches[-1].query_pos
    min_ext = min(match.target_pos for match in matches)
    max_ext = max(match.target_pos for match in matches)
    if max_cur - min_cur < min_overlap or max_ext - min_ext < min_overlap:
        return []
    if params["check_overhang"] and not params["force_local"]:
        if min(min_cur, min_ext) > int(params["maximum_overhang"]):
            return []
        if min(cur_len - max_cur, ext_len - max_ext) > int(params["maximum_overhang"]):
            return []

    work_matches = list(matches)
    score_table = [0] * len(work_matches)
    backtrack_table = [-1] * len(work_matches)

    ext_sorted = ext_len > cur_len
    if ext_sorted:
        work_matches.sort(key=lambda match: match.target_pos)

    for i in range(1, len(score_table)):
        max_score = 0
        max_id = 0
        cur_next = work_matches[i].query_pos
        ext_next = work_matches[i].target_pos

        for j in range(i - 1, -1, -1):
            cur_prev = work_matches[j].query_pos
            ext_prev = work_matches[j].target_pos
            cur_delta = cur_next - cur_prev
            ext_delta = ext_next - ext_prev
            jump_div = abs(cur_delta - ext_delta)
            if (
                0 < cur_delta < max_jump
                and 0 < ext_delta < max_jump
                and jump_div <= max_gap
            ):
                match_score = min(min(cur_delta, ext_delta), kmer_size)
                gap_penalty = lg_gap if jump_div > gap_jump_threshold else sm_gap
                gap_cost = int(gap_penalty * jump_div)
                next_score = score_table[j] + match_score - gap_cost
                if next_score > max_score:
                    max_score = next_score
                    max_id = j
                    if jump_div == 0 and cur_delta < kmer_size:
                        break
            if ext_sorted and ext_next - ext_prev > max_jump:
                break
            if not ext_sorted and cur_next - cur_prev > max_jump:
                break

        score_table[i] = max(max_score, kmer_size)
        if max_score > kmer_size:
            backtrack_table[i] = max_id

    ext_overlaps: list[Overlap] = []
    ordered_scores = sorted(range(len(backtrack_table)), key=lambda idx: -score_table[idx])
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
            cur_id=query_id,
            cur_begin=work_matches[first_match].query_pos,
            cur_end=work_matches[last_match].query_pos + kmer_size - 1,
            cur_len=cur_len,
            ext_id=ext_id,
            ext_begin=work_matches[first_match].target_pos,
            ext_end=work_matches[last_match].target_pos + kmer_size - 1,
            ext_len=ext_len,
            score=score_table[last_match] - score_table[first_match] + kmer_size - 1,
            seq_divergence=0.0,
        )

        if not overlap_test(overlap, params):
            continue

        filtered_count = 0
        for position in filtered_positions:
            if position < overlap.cur_begin:
                continue
            if position > overlap.cur_end:
                break
            filtered_count += 1

        norm_len = f32(float(max(overlap.cur_range(), overlap.ext_range()) - filtered_count))
        match_rate = f32(f32(float(chain_length) * float(params["sample_rate"])) / norm_len)
        match_rate = min(match_rate, f32(1.0))
        log_input = f32(f32(1.0) / match_rate)
        overlap.seq_divergence = f32(f32(cxx_logf(log_input)) / f32(kmer_size))
        ext_overlaps.append(overlap)

    ext_overlaps.sort(key=lambda overlap: -overlap.score)
    if params["only_max_ext"]:
        primary_overlaps = ext_overlaps[:1]
    else:
        primary_overlaps = []
        for overlap in ext_overlaps:
            is_contained = any(
                overlap.contained_by(primary) and primary.score > overlap.score
                for primary in primary_overlaps
            )
            if not is_contained:
                primary_overlaps.append(overlap)

    detected = []
    for overlap in primary_overlaps:
        if overlap.seq_divergence < float(params["max_divergence"]):
            detected.append(overlap)
    return detected


def replay_fixture(fixture_dir: Path) -> tuple[list[Overlap], dict]:
    manifest = load_manifest(fixture_dir)
    require_supported_shape(manifest)
    files = manifest["files"]
    query_id = int(manifest["query_id"])
    candidates = load_candidates(fixture_dir / files["candidates"], query_id)
    filtered_positions = load_filtered_positions(fixture_dir / files["filtered_positions"])
    targets = load_targets(fixture_dir / files["targets"])

    detected: list[Overlap] = []
    start = 0
    while start < len(candidates):
        if int(manifest["parameters"]["max_overlaps"]) and (
            len(detected) >= int(manifest["parameters"]["max_overlaps"])
        ):
            break
        end = start + 1
        while end < len(candidates) and candidates[start].target_id == candidates[end].target_id:
            end += 1
        detected.extend(
            chain_target(candidates[start:end], manifest, targets, filtered_positions)
        )
        start = end

    summary = {
        "schema": "cuflye-overlap-replay-result-v0",
        "status": "ok",
        "fixture_dir": str(fixture_dir.resolve()),
        "query_id": query_id,
        "candidate_records": len(candidates),
        "target_records": len(targets),
        "filtered_positions": len(filtered_positions),
        "overlap_records": len(detected),
        "supported_shape": {
            "nucl_alignment": False,
            "partition_bad_mappings": False,
            "keep_alignment": False,
        },
    }
    return detected, summary


def write_overlaps(overlaps: list[Overlap], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        for overlap in overlaps:
            handle.write(overlap.as_tsv())
            handle.write("\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture_dir", help="M4b overlap replay fixture directory")
    parser.add_argument("--output", required=True, help="Output overlap-range-v1 TSV")
    parser.add_argument("--json-output", help="Write replay summary JSON")
    args = parser.parse_args(argv)

    try:
        overlaps, summary = replay_fixture(Path(args.fixture_dir))
        write_overlaps(overlaps, Path(args.output))
        summary["output"] = str(Path(args.output).resolve())
    except ReplayError as exc:
        print(f"Overlap replay failed: {exc}", file=sys.stderr)
        if args.json_output:
            Path(args.json_output).write_text(
                json.dumps({"status": "failed", "error": str(exc)}, indent=2) + "\n",
                encoding="utf-8",
            )
        return 1

    if args.json_output:
        Path(args.json_output).write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    else:
        print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
