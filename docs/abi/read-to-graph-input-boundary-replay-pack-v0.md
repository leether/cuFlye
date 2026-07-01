# cuFlye Read-To-Graph Input Boundary Replay Pack v0

Status: proposed

Introduced: M6b

Scope: a bounded subset of M6a `read-to-graph-input-boundary-v0` query records.

## Purpose

`cuflye-read-to-graph-input-boundary-replay-pack-v0` turns the M6a Flye-side
input-boundary oracle into a deterministic external pack. The pack is the last
CPU-only handoff before a CUDA candidate/minimizer prototype: it must contain
enough stable data to reconstruct the `chain_input` rows that Flye feeds into
`ReadAligner::chainReadAlignments`.

M6b does not feed replayed or GPU-generated data back into Flye graph logic.

## Files

| File | Meaning |
| --- | --- |
| `manifest.json` | Pack schema, source dump hash, selected query ids, per-query counts/hashes, timing provenance, and unsupported-shape exclusions. |
| `queries.tsv` | One stable summary row per selected query. |
| `raw-overlaps.tsv` | Raw overlap rows from M6a after `quickSeqOverlaps(seqId)`. |
| `oracle.chain-input.tsv` | M6a `chain_input` rows for the selected queries. |

## `queries.tsv`

```text
query_id<TAB>raw_overlap_count<TAB>chain_input_count<TAB>filtered_out_raw_overlap_count<TAB>quick_overlap_wall_ms<TAB>input_filter_sort_wall_ms<TAB>cpu_chain_dp_wall_ms<TAB>cpu_divergence_filter_wall_ms
```

Timing columns are profiling provenance only. They are excluded from canonical
pack equivalence and replay diff hashes.

## `raw-overlaps.tsv`

```text
query_id<TAB>source_order<TAB>raw_overlap_count<TAB>chain_input_count<TAB>read_id<TAB>read_begin<TAB>read_end<TAB>read_len<TAB>edge_seq_id<TAB>edge_begin<TAB>edge_end<TAB>edge_len<TAB>edge_id<TAB>score<TAB>seq_divergence<TAB>passes_chain_input_filter
```

`source_order` is the raw-overlap order reported by M6a. The future CUDA
candidate/minimizer prototype may use it for debugging, but replay semantics do
not depend on it after filter/sort is reconstructed.

## `oracle.chain-input.tsv`

```text
query_id<TAB>order<TAB>raw_overlap_count<TAB>chain_input_count<TAB>read_id<TAB>read_begin<TAB>read_end<TAB>read_len<TAB>edge_seq_id<TAB>edge_begin<TAB>edge_end<TAB>edge_len<TAB>edge_id<TAB>score<TAB>seq_divergence<TAB>passes_chain_input_filter
```

This file is the selected M6a oracle. A replay implementation must reproduce
this file canonically before any CUDA output can be treated as graph-facing.

## Replay Contract

A CPU replay implementation must:

- validate the source M6a dump before pack export;
- read `raw-overlaps.tsv`;
- keep rows where `passes_chain_input_filter == 1`;
- fail closed if selected `chain_input` ordering would be ambiguous;
- sort filtered rows by `read_begin`;
- assign zero-based per-query `order`;
- emit `oracle.chain-input.tsv` format;
- canonical-diff the replay output against `oracle.chain-input.tsv`.

The M6b supported shape requires unique `read_begin` among selected
`chain_input` rows. This keeps replay deterministic because Flye's local C++
sort compares only `curBegin` at this boundary.

## Supported Shape

The M6b packer must reject or exclude a query when:

- `raw_overlap_count == 0`;
- `chain_input_count == 0`;
- `raw_overlap_count` exceeds the configured pack limit;
- `chain_input_count` exceeds the configured pack limit;
- selected `chain_input` rows do not have unique `read_begin` values.

Unsupported exclusions are recorded in `manifest.json`. Silent inclusion is not
allowed.

## Non-Goals

M6b does not:

- run CUDA;
- reconstruct Flye minimizer buckets or original read/edge sequences;
- replace `quickSeqOverlaps`;
- feed replayed rows into `ReadAligner::chainReadAlignments`;
- make a Flye stage or whole-Flye speed claim.

## Follow-On Contract

M6c should consume this pack with a CUDA raw-overlap filter/sort replay
prototype and prove that CUDA-produced `chain_input` rows canonical-diff
`match` against `oracle.chain-input.tsv` for every selected query.

A later milestone needs a richer source pack before claiming full
candidate/minimizer generation, because M6b intentionally does not store query
sequences, graph edge sequences, VertexIndex minimizer buckets, k-mer
parameters, or the internals needed to reimplement `quickSeqOverlaps`.
