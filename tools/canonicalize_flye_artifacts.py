#!/usr/bin/env python3
"""Canonicalize Flye M0 artifacts and compute stable hashes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from collections import Counter, defaultdict
from typing import Iterator


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


def canonical_repeat_graph_dump(path: Path) -> str:
    records: list[dict] = []
    passthrough: list[str] = []
    current: dict | None = None

    for raw_line in read_text(path).splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        parts = stripped.split()
        if parts and parts[0] == "Edge" and len(parts) >= 9:
            current = {
                "parts": parts,
                "sequences": [],
            }
            records.append(current)
        elif parts and parts[0] == "Sequence" and current is not None:
            current["sequences"].append(parts)
        else:
            passthrough.append(stripped)
            current = None

    if not records:
        return canonical_plain(path)

    incoming: dict[str, list[str]] = defaultdict(list)
    outgoing: dict[str, list[str]] = defaultdict(list)
    nodes: set[str] = set()

    for record in records:
        parts = record["parts"]
        edge_id = parts[1]
        start_node = parts[2]
        end_node = parts[3]
        nodes.add(start_node)
        nodes.add(end_node)
        outgoing[start_node].append(edge_id)
        incoming[end_node].append(edge_id)

    signatures = {
        node: (tuple(sorted(incoming[node])), tuple(sorted(outgoing[node])))
        for node in nodes
    }
    counts = Counter(signatures.values())

    # If the incident-edge signature is not unique, do not canonicalize node ids:
    # collapsing symmetric nodes would hide a real ambiguity.
    if any(count > 1 for count in counts.values()):
        return canonical_plain(path)

    node_labels = {
        node: f"N{idx:04d}"
        for idx, node in enumerate(sorted(nodes, key=lambda node: signatures[node]))
    }

    def edge_key(record: dict) -> tuple[int, str]:
        edge_id = record["parts"][1]
        try:
            return int(edge_id), edge_id
        except ValueError:
            return 0, edge_id

    out: list[str] = []
    for record in sorted(records, key=edge_key):
        parts = list(record["parts"])
        parts[2] = node_labels[parts[2]]
        parts[3] = node_labels[parts[3]]
        out.append("\t".join(parts))
        for seq_parts in record["sequences"]:
            out.append("\t" + "\t".join(seq_parts))

    if passthrough:
        out.extend(sorted(passthrough))

    return "\n".join(out) + "\n"


def artifact_kind(path: Path, explicit: str | None = None) -> str:
    if explicit and explicit != "auto":
        return explicit
    name = path.name
    suffix = path.suffix.lower()
    if suffix in {".fa", ".fasta", ".fna"}:
        return "fasta"
    if suffix == ".gfa":
        return "gfa"
    if name == "repeat_graph_dump":
        return "repeat_graph_dump"
    if name in {"read_alignment_dump", "assembly_info.txt"}:
        return "plain"
    return "plain"


def canonicalize(path: Path, kind: str | None = None, sort_fasta_records: bool = False) -> str:
    detected = artifact_kind(path, kind)
    if detected == "fasta":
        return canonical_fasta(path, sort_records=sort_fasta_records)
    if detected == "gfa":
        return canonical_gfa(path)
    if detected == "repeat_graph_dump":
        return canonical_repeat_graph_dump(path)
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
    parser.add_argument("--artifact", default="auto", choices=["auto", "fasta", "gfa", "plain", "repeat_graph_dump"])
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
