#!/usr/bin/env python3
"""Generate sampled pack-dump-v0 fixtures and CUDA worker batch requests."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


DNA_COMPLEMENT = str.maketrans("ACGTacgt", "TGCAtgca")
SAFE_LABEL = re.compile(r"^[A-Za-z0-9_.-]+$")


class BatchPlannerError(ValueError):
    pass


@dataclass(frozen=True)
class ReadRecord:
    query_id: int
    sequence: str


@dataclass(frozen=True)
class IndexRecord:
    target_id: int
    target_pos: int
    target_strand: str
    lookup_kmer: str
    raw_line: str


@dataclass(frozen=True)
class SampleSpec:
    label: str
    offset: int
    length_text: str


def read_lines(path: Path) -> list[str]:
    if not path.is_file():
        raise BatchPlannerError(f"missing required file: {path}")
    return path.read_text(encoding="utf-8").splitlines()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_source_read(path: Path) -> ReadRecord:
    rows = [line for line in read_lines(path) if line]
    if len(rows) != 1:
        raise BatchPlannerError(f"{path} must contain exactly one source query read")
    fields = rows[0].split("\t")
    if len(fields) != 2:
        raise BatchPlannerError(f"{path} must have query_id<TAB>sequence rows")
    sequence = fields[1].upper()
    invalid = sorted(set(sequence) - set("ACGT"))
    if invalid:
        raise BatchPlannerError(f"{path} contains unsupported DNA bases: {''.join(invalid)}")
    return ReadRecord(query_id=int(fields[0]), sequence=sequence)


def parse_index(path: Path) -> list[IndexRecord]:
    records: list[IndexRecord] = []
    for line_no, line in enumerate(read_lines(path), 1):
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            raise BatchPlannerError(f"{path}:{line_no}: expected 4 tab-separated fields")
        target_id, target_pos, target_strand, lookup_kmer = fields
        if target_strand not in {"+", "-"}:
            raise BatchPlannerError(f"{path}:{line_no}: target strand must be + or -")
        records.append(
            IndexRecord(
                target_id=int(target_id),
                target_pos=int(target_pos),
                target_strand=target_strand,
                lookup_kmer=lookup_kmer.upper(),
                raw_line=line,
            )
        )
    return records


def parse_repetitive(path: Path) -> list[str]:
    return [line.upper() for line in read_lines(path) if line]


def reverse_complement(sequence: str) -> str:
    return sequence.translate(DNA_COMPLEMENT)[::-1].upper()


def standard_kmer(sequence: str) -> str:
    sequence = sequence.upper()
    rc = reverse_complement(sequence)
    return sequence if sequence <= rc else rc


def lookup_kmers(sequence: str, kmer_size: int) -> set[str]:
    if len(sequence) < kmer_size:
        return set()
    return {
        standard_kmer(sequence[offset : offset + kmer_size])
        for offset in range(0, len(sequence) - kmer_size + 1)
    }


def parse_sample(text: str) -> SampleSpec:
    fields = text.split(":")
    if len(fields) != 3:
        raise BatchPlannerError(
            f"invalid --sample {text!r}; expected LABEL:OFFSET:LENGTH"
        )
    label, offset_text, length_text = fields
    if not SAFE_LABEL.match(label):
        raise BatchPlannerError(f"invalid sample label {label!r}")
    offset = int(offset_text)
    if offset < 0:
        raise BatchPlannerError(f"sample {label}: offset must be non-negative")
    if length_text != "full" and int(length_text) <= 0:
        raise BatchPlannerError(f"sample {label}: length must be positive or full")
    return SampleSpec(label=label, offset=offset, length_text=length_text)


def sample_sequence(source: ReadRecord, spec: SampleSpec, kmer_size: int) -> str:
    length = len(source.sequence) - spec.offset if spec.length_text == "full" else int(spec.length_text)
    if length < kmer_size:
        raise BatchPlannerError(
            f"sample {spec.label}: length {length} is smaller than k-mer size {kmer_size}"
        )
    end = spec.offset + length
    if end > len(source.sequence):
        raise BatchPlannerError(
            f"sample {spec.label}: range {spec.offset}:{end} exceeds source length "
            f"{len(source.sequence)}"
        )
    return source.sequence[spec.offset:end]


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def build_sample_pack(
    *,
    out_dir: Path,
    source: ReadRecord,
    index_records: list[IndexRecord],
    repetitive_kmers: list[str],
    spec: SampleSpec,
    kmer_size: int,
) -> dict:
    sequence = sample_sequence(source, spec, kmer_size)
    sample_kmers = lookup_kmers(sequence, kmer_size)
    filtered_index = [record for record in index_records if record.lookup_kmer in sample_kmers]
    filtered_repetitive = sorted({kmer for kmer in repetitive_kmers if kmer in sample_kmers})
    query_windows = len(sequence) - kmer_size + 1
    sample_dir = out_dir / "packs" / spec.label
    reads_tsv = sample_dir / "reads.tsv"
    index_tsv = sample_dir / "index.tsv"
    repetitive_tsv = sample_dir / "repetitive-kmers.tsv"
    manifest = sample_dir / "sample-manifest.json"

    write_text(reads_tsv, f"{source.query_id}\t{sequence}\n")
    write_text(index_tsv, "".join(f"{record.raw_line}\n" for record in filtered_index))
    write_text(repetitive_tsv, "".join(f"{kmer}\n" for kmer in filtered_repetitive))

    payload = {
        "schema": "cuflye-sampled-pack-v0",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_query_id": source.query_id,
        "sample_label": spec.label,
        "sample_offset": spec.offset,
        "sample_length": len(sequence),
        "kmer_size": kmer_size,
        "query_windows": query_windows,
        "lookup_kmers": len(sample_kmers),
        "index_entries": len(filtered_index),
        "repetitive_kmers": len(filtered_repetitive),
        "estimated_pair_count": query_windows * len(filtered_index),
        "files": {
            "reads_tsv": str(reads_tsv.resolve()),
            "index_tsv": str(index_tsv.resolve()),
            "repetitive_kmers_tsv": str(repetitive_tsv.resolve()),
        },
        "sha256": {
            "reads_tsv": sha256_file(reads_tsv),
            "index_tsv": sha256_file(index_tsv),
            "repetitive_kmers_tsv": sha256_file(repetitive_tsv),
        },
    }
    write_text(manifest, json.dumps(payload, indent=2, sort_keys=True) + "\n")
    payload["manifest"] = str(manifest.resolve())
    return payload


def build_worker_request(
    *,
    out_dir: Path,
    sample: dict,
    request_ordinal: int,
    device: int,
    memory_budget_bytes: int | None,
) -> dict:
    label = sample["sample_label"]
    output_dir = out_dir / "worker"
    output_dir.mkdir(parents=True, exist_ok=True)
    request = {
        "schema": "cuflye-worker-request-v0",
        "request_id": f"sample-{request_ordinal:03d}-{label}",
        "adapter_mode": "pack-dump-v0",
        "candidate_abi": "candidate-record-v1",
        "kmer_size": sample["kmer_size"],
        "device": device,
        "reads_tsv": sample["files"]["reads_tsv"],
        "index_tsv": sample["files"]["index_tsv"],
        "repetitive_kmers_tsv": sample["files"]["repetitive_kmers_tsv"],
        "output_tsv": str((output_dir / f"{label}.worker.candidates.tsv").resolve()),
        "backend_json": str((output_dir / f"{label}.backend.json").resolve()),
        "response_json": str((output_dir / f"{label}.response.json").resolve()),
        "query_id": sample["source_query_id"],
        "expected_read_count": 1,
        "expected_index_entries": sample["index_entries"],
    }
    if memory_budget_bytes is not None:
        request["memory_budget_bytes"] = memory_budget_bytes
    return request


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-pack-dir", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--kmer-size", required=True, type=int)
    parser.add_argument("--sample", action="append", required=True,
                        help="Sample as LABEL:OFFSET:LENGTH; LENGTH may be full")
    parser.add_argument("--device", type=int, default=0)
    parser.add_argument("--memory-budget-bytes", type=int)
    parser.add_argument("--order", choices=("estimated-pair-desc", "input"),
                        default="estimated-pair-desc")
    parser.add_argument("--plan-json", type=Path)
    parser.add_argument("--requests-jsonl", type=Path)
    args = parser.parse_args()

    if args.kmer_size <= 0:
        raise BatchPlannerError("--kmer-size must be positive")
    if args.memory_budget_bytes is not None and args.memory_budget_bytes <= 0:
        raise BatchPlannerError("--memory-budget-bytes must be positive")

    source_pack_dir = args.source_pack_dir.resolve()
    out_dir = args.out_dir.resolve()
    plan_json = (args.plan_json or out_dir / "batch-plan.json").resolve()
    requests_jsonl = (args.requests_jsonl or out_dir / "requests.jsonl").resolve()
    sample_specs = [parse_sample(text) for text in args.sample]
    labels = [spec.label for spec in sample_specs]
    if len(labels) != len(set(labels)):
        raise BatchPlannerError("sample labels must be unique")

    source = parse_source_read(source_pack_dir / "reads.tsv")
    index_records = parse_index(source_pack_dir / "index.tsv")
    repetitive_kmers = parse_repetitive(source_pack_dir / "repetitive-kmers.tsv")
    out_dir.mkdir(parents=True, exist_ok=True)

    samples = [
        build_sample_pack(
            out_dir=out_dir,
            source=source,
            index_records=index_records,
            repetitive_kmers=repetitive_kmers,
            spec=spec,
            kmer_size=args.kmer_size,
        )
        for spec in sample_specs
    ]
    request_samples = list(samples)
    if args.order == "estimated-pair-desc":
        request_samples.sort(
            key=lambda sample: (
                sample["estimated_pair_count"],
                sample["sample_length"],
                sample["sample_label"],
            ),
            reverse=True,
        )

    requests = [
        build_worker_request(
            out_dir=out_dir,
            sample=sample,
            request_ordinal=index + 1,
            device=args.device,
            memory_budget_bytes=args.memory_budget_bytes,
        )
        for index, sample in enumerate(request_samples)
    ]

    write_text(
        requests_jsonl,
        "".join(json.dumps(request, sort_keys=True) + "\n" for request in requests),
    )
    plan = {
        "schema": "cuflye-worker-batch-plan-v0",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_pack_dir": str(source_pack_dir),
        "source_query_id": source.query_id,
        "source_read_length": len(source.sequence),
        "kmer_size": args.kmer_size,
        "device": args.device,
        "memory_budget_bytes": args.memory_budget_bytes,
        "order": args.order,
        "request_count": len(requests),
        "request_order": [sample["sample_label"] for sample in request_samples],
        "cpu_fallback_requests": 0,
        "requests_jsonl": str(requests_jsonl),
        "samples": samples,
        "requests": requests,
    }
    write_text(plan_json, json.dumps(plan, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "plan_json": str(plan_json),
        "requests_jsonl": str(requests_jsonl),
        "request_count": len(requests),
        "source_query_id": source.query_id,
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BatchPlannerError as exc:
        raise SystemExit(f"cuFlye worker batch planning failed: {exc}")
