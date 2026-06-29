# cuFlye Candidate Record ABI v1

Status: active

Introduced: M1c

Scope: overlap candidate records emitted before Flye CPU chaining in
`OverlapDetector::getSeqOverlaps`.

## Purpose

This ABI defines the minimum contract a future CUDA candidate backend must
satisfy before its output can be fed into Flye's existing CPU chaining, repeat
graph, and polishing stages.

M1a and M1b proved that cuFlye can dump and compare Flye's current CPU
candidate list. M1c turns that proof surface into a stable record contract.

## Record Semantics

Each record is one raw k-mer hit produced after Flye's existing candidate
filters:

- repetitive k-mers are skipped;
- k-mers absent from the vertex index are skipped;
- the exact self hit with the same read id and same position is skipped;
- no chaining, overlap scoring, or graph logic has run yet.

The record is a candidate hit, not a validated overlap.

## TSV Encoding

Candidate dump files are UTF-8 compatible, tab-separated text with no header.
Each non-empty line must contain exactly six fields:

```text
query_id<TAB>query_pos<TAB>kmer<TAB>target_id<TAB>target_pos<TAB>target_strand<LF>
```

Fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `query_id` | signed decimal int64 | Flye `FastaRecord::Id::signedId()` for the query record. |
| `query_pos` | unsigned decimal int64 | Zero-based k-mer position in the query sequence. |
| `kmer` | unsigned decimal uint64 | Flye `Kmer::numRepr()` for the query k-mer. |
| `target_id` | signed decimal int64 | Flye `FastaRecord::Id::signedId()` for the indexed target record. |
| `target_pos` | unsigned decimal int64 | Zero-based k-mer position in the target sequence. |
| `target_strand` | enum | `+` when `target_id.strand()` is true, otherwise `-`. |

No extra columns, comments, blank records, or header rows are allowed.

## Equality Contract

Backends are equivalent when their candidate files contain the same multiset of
records after canonical sorting by:

```text
query_id, query_pos, kmer, target_id, target_pos, target_strand
```

Raw file order is not part of the correctness contract unless a producer
explicitly opts into canonical order. CUDA backends may emit records in any
deterministic or non-deterministic order if canonical sorting produces the same
records as the CPU oracle.

For performance profiling, raw SHA-256 is still recorded. It is a reproducibility
signal, not the primary correctness gate.

## Producer Requirements

A backend producing ABI v1 records must:

- preserve all six fields exactly as decimal text;
- preserve duplicate records;
- preserve the CPU oracle's candidate filtering semantics;
- avoid lossy integer narrowing;
- never silently fall back to a different backend;
- fail non-zero on unsupported backend names or memory-budget violations;
- report enough metadata to identify backend name, Flye commit, cuFlye commit,
  fixture, read type, genome size, thread count, and dump path.

## CUDA Backend Contract

The first CUDA backend must expose the same logical boundary as the current CPU
candidate collection step:

```text
input:  query sequence, vertex index, repetitive-kmer filter, k-mer size
output: ABI v1 candidate records before CPU chaining
```

It must not change:

- chaining;
- divergence statistics;
- overlap scoring;
- repeat graph construction;
- graph simplification;
- polishing.

The initial CUDA gate is candidate-list equivalence only. Downstream Flye
artifact equivalence remains a separate acceptance gate.

## Memory Budget Contract

For M1c and the first CUDA prototype, memory reporting is mandatory:

- record count;
- raw dump size in bytes;
- raw SHA-256;
- canonical SHA-256 when requested;
- peak process RSS when a benchmark wrapper captures it;
- GPU device memory allocated and peak device memory when a CUDA backend exists.

The CUDA backend must fail clearly if a requested dataset exceeds its configured
device-memory budget. It must not truncate candidate records.

## Gate Commands

Validate one candidate file:

```sh
tools/validate_candidate_dump.py path/to/candidates.tsv \
  --expect-records 29035928 \
  --expect-raw-sha256 5e55b79e3cda21ce4d7e5e101a65f30b8fa9c3ba50b542faadbbb27d5c4bfebd
```

Validate and compute canonical SHA-256:

```sh
tools/validate_candidate_dump.py path/to/candidates.tsv \
  --compute-canonical-sha256 \
  --expect-canonical-sha256 97ec5f51c034e5a8a8eaa70d4c3d4ced5513f7ee93ad367671b756814310086b
```

Compare two backends:

```sh
tools/diff_candidate_dumps.py cpu.tsv cuda.tsv
```

The CUDA backend is not eligible to feed downstream Flye stages until both the
ABI validator and candidate diff gates pass.

See `docs/abi/cuda-candidate-backend-v0.md` for the pre-kernel CUDA backend
stub contract.
