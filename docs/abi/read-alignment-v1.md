# cuFlye Read Alignment ABI v1

Status: active

Introduced: M5a

Scope: Flye `ReadAligner::alignReads` output after read-to-repeat-graph
alignment chains are accepted and divergence-filtered, before repeat graph
simplification consumes them.

## Purpose

`read-alignment-v1` is the CPU oracle contract for future read-to-graph CUDA
work. It captures the `GraphAlignment` vector owned by `ReadAligner` as a flat
TSV so a future CUDA path can be compared before it is allowed to influence
repeat resolution, multiplicity inference, or output generation.

## Deterministic Mode

The M5a runtime dump requires `--threads 1`. `ReadAligner::alignReads` appends
accepted chains from a parallel loop, so raw chain order is not a stable oracle
when multiple threads are used. cuFlye fails closed if
`CUFLYE_READ_ALIGNMENT_DUMP` is enabled with more than one thread.

## TSV Fields

Each row has 13 tab-separated fields:

```text
chain_id<TAB>segment_id<TAB>read_id<TAB>read_begin<TAB>read_end<TAB>read_len<TAB>edge_id<TAB>edge_seq_id<TAB>edge_begin<TAB>edge_end<TAB>edge_len<TAB>score<TAB>seq_divergence
```

| Field | Type | Meaning |
| --- | --- | --- |
| `chain_id` | uint63 | Raw chain ordinal in `_readAlignments` for deterministic single-thread runs. |
| `segment_id` | uint63 | Segment ordinal inside the chain. |
| `read_id` | signed int64 | Read id using Flye `FastaRecord::Id::signedId()`. |
| `read_begin` | uint63 | Inclusive begin coordinate on the read. |
| `read_end` | uint63 | Inclusive end coordinate on the read. |
| `read_len` | uint63 | Read length. |
| `edge_id` | signed int64 | Repeat-graph edge id using Flye signed id orientation. |
| `edge_seq_id` | signed int64 | Edge-sequence id from the `OverlapRange` target. |
| `edge_begin` | uint63 | Inclusive begin coordinate on the edge sequence. |
| `edge_end` | uint63 | Inclusive end coordinate on the edge sequence. |
| `edge_len` | uint63 | Edge-sequence length. |
| `score` | signed int64 | Flye chain score stored in `OverlapRange::score`. |
| `seq_divergence` | float | Segment divergence stored in `OverlapRange::seqDivergence`. |

## Semantics

Rows are emitted after:

- graph edge sequences have been indexed;
- read/edge overlaps have been collected;
- per-read edge alignments have been chained;
- chain base divergence has been computed;
- chains above `read_align_ovlp_divergence` have been rejected;
- complement chains have been added.

The dump does not replace Flye's existing `read_alignment_dump`; it gives cuFlye
a strict typed oracle that is easier to validate and diff.

## Ordering

The runtime dump preserves `_readAlignments` order and segment order. Equality
checks may canonicalize by sorting on all fields in TSV order, but M5a proof
runs must still use `--threads 1` to keep `chain_id` stable.

## Failure Rules

A valid `read-alignment-v1` file:

- is UTF-8 text;
- has no header;
- has exactly 13 fields per non-empty row;
- has at least one row;
- has non-zero signed ids for `read_id`, `edge_id`, and `edge_seq_id`;
- has coordinates satisfying `0 <= begin <= end < len`;
- has positive read and edge lengths;
- has finite non-negative `seq_divergence`;
- ends every row with LF.

## Non-Goals

This ABI does not define:

- raw read-to-edge candidate hits;
- edlib traceback or base-level alignment CIGAR;
- graph mutation after alignment consumption;
- approximate equivalence tolerances for future CUDA divergence calculations.
