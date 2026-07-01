# cuFlye Read-To-Graph Minimizer Source Pack v0

Status: accepted

Introduced: M6d

Scope: selected Flye `ReadAligner::alignReads` read-to-graph queries.

## Purpose

`cuflye-read-to-graph-minimizer-source-pack-v0` captures the source data needed
to move beyond M6b raw-overlap replay toward true `quickSeqOverlaps` and
candidate/minimizer generation. It is still a CPU oracle pack. No CUDA output
is fed into Flye graph logic.

M6d intentionally records a missing-semantics ledger when full raw-overlap
replay is not yet implemented. That ledger is part of the contract: the pack
must say exactly what remains before a CUDA implementation can claim to replace
`quickSeqOverlaps`.

## Layout

The pack root contains one directory per selected positive query id:

```text
<pack-root>/
  query_5/
    manifest.json
    query.tsv
    query-minimizers.tsv
    index-buckets.tsv
    full-query-hits.tsv
    edge-sequences.tsv
    raw-overlaps.tsv
    oracle.chain-input.tsv
    missing-semantics.json
```

## Files

| File | Meaning |
| --- | --- |
| `manifest.json` | Pack schema, query id, parameters, counts, file names, and replay status. |
| `query.tsv` | Selected query id and full read sequence. |
| `query-minimizers.tsv` | Query minimizers generated with Flye's `yieldMinimizers` window. |
| `index-buckets.tsv` | VertexIndex bucket entries for non-repetitive query minimizers. |
| `full-query-hits.tsv` | Optional M6f extension with the full `OverlapDetector::IterKmers` query-hit stream. |
| `edge-sequences.tsv` | Graph edge-sequence ids, lengths, and sequence strings referenced by buckets or overlap oracle rows. |
| `raw-overlaps.tsv` | M6a raw-overlap oracle rows for the query. |
| `oracle.chain-input.tsv` | M6a chain-input oracle rows for the query. |
| `missing-semantics.json` | Precise missing semantics that prevent full raw-overlap replay at M6d. |

## Query Minimizer TSV

```text
query_id<TAB>query_pos<TAB>query_kmer_repr<TAB>standard_kmer_repr<TAB>standard_revcomp<TAB>is_repetitive<TAB>kmer_freq
```

`query_kmer_repr` is the original query k-mer representation. `standard_kmer_repr`
is the representation after Flye `Kmer::standardForm`. `standard_revcomp` is
`1` when the standard form is the reverse complement.

## Index Bucket TSV

```text
query_id<TAB>query_pos<TAB>standard_kmer_repr<TAB>target_edge_seq_id<TAB>target_pos
```

Rows are emitted by iterating Flye `VertexIndex::iterKmerPos` for each
non-repetitive query minimizer with non-zero frequency.

## Full Query-Hit TSV

```text
query_id<TAB>source_order<TAB>query_pos<TAB>query_kmer_repr<TAB>standard_kmer_repr<TAB>standard_revcomp<TAB>is_repetitive<TAB>kmer_freq<TAB>target_edge_seq_id<TAB>target_pos
```

`full-query-hits.tsv` is optional for M6d packs and present for M6f packs. It
captures the full query-side stream used by Flye's CPU
`OverlapDetector::getSeqOverlaps`: iterate all query k-mers with `IterKmers`,
skip repetitive k-mers and k-mers with zero `VertexIndex` frequency, then emit
one row for each `VertexIndex::iterKmerPos` target. `source_order` preserves
the pre-sort insertion order before replay sorts by target `FastaRecord::Id`
and query position.

## Oracle TSVs

`raw-overlaps.tsv` uses `cuflye-read-to-graph-raw-overlap-v0`.

`oracle.chain-input.tsv` uses `cuflye-read-to-graph-chain-input-v0`.

These match the M6b replay-pack stable row contracts.

## Missing Semantics

At M6d, validation must report `missing-semantics-ledger` rather than claiming
full replay when any of these remain outside the pack/replay implementation:

- `KmerMatch` grouping and chain DP inside `OverlapDetector::getSeqOverlaps`;
- `OverlapDetector::overlapTest` filtering semantics;
- optional nucleotide/base alignment refinement;
- `maxOverlaps` and `onlyMaxExt` final selection behavior.

## Determinism

Source-pack capture requires `--threads 1` and an explicit
`CUFLYE_READ_TO_GRAPH_SOURCE_PACK_QUERY_IDS` allowlist. Manifests must not store
absolute output paths or timestamps so that two exports can be canonical-diffed.

## Non-Goals

M6d does not:

- run CUDA;
- replace `quickSeqOverlaps`;
- feed source-pack data into Flye graph mutation;
- prove a Flye stage or whole-Flye speedup.

## Follow-On Contract

The next CUDA-facing milestone should consume the source pack only after a CPU
replay checker either reproduces the selected raw-overlap oracle or narrows the
missing-semantics ledger to the exact remaining Flye operations.

## M6e Replay Contract

`tools/replay_read_to_graph_source_pack.py` consumes this pack without a live
Flye process and emits:

- `replay.raw-overlaps.tsv`;
- `replay.summary.json`;
- `replay.groups.json`.

The replay reconstructs these Flye `OverlapDetector::getSeqOverlaps` semantics
for the read-to-graph detector shape:

- materialize `KmerMatch`-like records from captured `VertexIndex` bucket hits;
- group matches by Flye `FastaRecord::Id` order;
- run Flye-style gap-aware chain DP for each target edge sequence;
- apply `overlapTest`;
- apply primary-overlap containment filtering for `onlyMaxExt=false`;
- apply the read-to-graph detector divergence gate with `maxDivergence=1.0`.

The M6e status is `match` only when replayed raw-overlap rows match the oracle
exactly. Otherwise it is `gap-ledger`: the replay is deterministic and records
the exact row-level differences plus the narrowed missing-semantics ledger.

For the accepted M6e proof, the main remaining gap is source completeness:
M6d captures minimizer bucket hits, while Flye's CPU path iterates all query
k-mers through `IterKmers` and keeps any non-repetitive k-mer that exists in
the minimizer-built `VertexIndex`. Those non-minimizer query hits can change
chain score, divergence, and in some cases coordinates. A CUDA replacement must
therefore either capture/recompute the full query-hit stream or prove the
minimizer-only stream is sufficient for a narrower supported shape.

M6f adds `full-query-hits.tsv` to remove that source-completeness gap while
preserving the older M6d files for compatibility.
