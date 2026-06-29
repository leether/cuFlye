#!/usr/bin/env python3
"""Canonicalize Flye M0 artifacts and compute stable hashes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Iterable, Iterator


DEFAULT_ARTIFACTS = [
    "00-assembly/draft_assembly.fasta",
    "20-repeat/repeat_graph_dump",
    "20-repeat/read_alignment_dump",
    "20-repeat/repeat_graph_edges.fasta",
    "30-contigger/graph_final.gfa",
    "30-contigger/graph_final.fasta",
    "assembly.fasta",
    "assembly_info.txt",
    "assembly_graph.gfa",
]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def canonical_plain(path: Path) -> str:
    lines = [line.rstrip() for line in read_text(path).splitlines()]
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n"


def parse_fasta(text: str) -> Iterator[tuple[str, str]]:
    header: str | None = None
    seq_parts: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(">"):
            if header is not None:
                yield header, "".join(seq_parts).upper()
            header = line[1:].strip()
            seq_parts = []
        else:
            seq_parts.append(line.replace(" ", ""))
    if header is not None:
        yield header, "".join(seq_parts).upper()


def canonical_fasta(path: Path, sort_records: bool = False) -> str:
    records = list(parse_fasta(read_text(path)))
    if sort_records:
        records.sort(key=lambda item: item[0])
    out: list[str] = []
    for header, sequence in records:
        out.append(f">{header}")
        out.append(sequence)
    return "\n".join(out) + "\n"


def canonical_gfa(path: Path) -> str:
    # Preserve order. For M0 we only normalize line endings/trailing whitespace;
    # semantic graph canonicalization can be added when GPU graph equivalence
    # needs it.
    return canonical_plain(path)


def artifact_kind(path: Path, explicit: str | None = None) -> str:
    if explicit and explicit != "auto":
        return explicit
    name = path.name
    suffix = path.suffix.lower()
    if suffix in {".fa", ".fasta", ".fna"}:
        return "fasta"
    if suffix == ".gfa":
        return "gfa"
    if name in {"repeat_graph_dump", "read_alignment_dump", "assembly_info.txt"}:
        return "plain"
    return "plain"


def canonicalize(path: Path, kind: str | None = None, sort_fasta_records: bool = False) -> str:
    detected = artifact_kind(path, kind)
    if detected == "fasta":
        return canonical_fasta(path, sort_records=sort_fasta_records)
    if detected == "gfa":
        return canonical_gfa(path)
    if detected == "plain":
        return canonical_plain(path)
    raise ValueError(f"Unsupported artifact kind: {detected}")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def manifest_for_run(run_dir: Path, sort_fasta_records: bool = False) -> dict:
    artifacts = []
    for rel_path in DEFAULT_ARTIFACTS:
        path = run_dir / rel_path
        if not path.exists():
            artifacts.append({
                "path": rel_path,
                "present": False,
            })
            continue
        text = canonicalize(path, sort_fasta_records=sort_fasta_records)
        artifacts.append({
            "path": rel_path,
            "present": True,
            "kind": artifact_kind(path),
            "bytes": path.stat().st_size,
            "canonical_sha256": sha256_text(text),
        })
    return {
        "run_dir": str(run_dir.resolve()),
        "sort_fasta_records": sort_fasta_records,
        "artifacts": artifacts,
    }


def write_output(text: str, output: str | None) -> None:
    if output:
        Path(output).write_text(text, encoding="utf-8")
    else:
        print(text, end="")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", help="Artifact path to canonicalize")
    parser.add_argument("--artifact", default="auto", choices=["auto", "fasta", "gfa", "plain"])
    parser.add_argument("--output", help="Write canonical text to this path")
    parser.add_argument("--hash", action="store_true", help="Print SHA256 of canonical text")
    parser.add_argument("--manifest", metavar="RUN_DIR", help="Emit artifact hash manifest for a Flye run directory")
    parser.add_argument("--sort-fasta-records", action="store_true", help="Sort FASTA records by header before hashing")
    args = parser.parse_args(argv)

    if args.manifest:
        manifest = manifest_for_run(Path(args.manifest), sort_fasta_records=args.sort_fasta_records)
        print(json.dumps(manifest, indent=2, sort_keys=True))
        return 0

    if not args.path:
        parser.error("path is required unless --manifest is used")

    canonical = canonicalize(Path(args.path), args.artifact, sort_fasta_records=args.sort_fasta_records)
    if args.hash:
        print(sha256_text(canonical))
    else:
        write_output(canonical, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
