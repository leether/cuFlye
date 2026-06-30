# cuFlye Overlap Range ABI v1

Status: active

Introduced: M4a

Scope: Flye `OverlapRange` records emitted after candidate chaining and overlap
filtering in `OverlapDetector::getSeqOverlaps`.

## Purpose

`overlap-range-v1` is the CPU oracle contract for M4 overlap chaining work. It
captures Flye's post-chain overlap ranges so a future CUDA implementation can be
compared before any output is allowed into downstream graph logic.

This ABI is downstream of `candidate-record-v1`:

- candidate records are raw k-mer hits;
- overlap ranges are chained, filtered `OverlapRange` objects.

## TSV Fields

Each row has 10 tab-separated fields:

```text
cur_id<TAB>cur_begin<TAB>cur_end<TAB>cur_len<TAB>ext_id<TAB>ext_begin<TAB>ext_end<TAB>ext_len<TAB>score<TAB>seq_divergence
```

| Field | Type | Meaning |
| --- | --- | --- |
| `cur_id` | signed int64 | Current/query read id using Flye `FastaRecord::Id::signedId()`. |
| `cur_begin` | uint63 | Inclusive current-read begin coordinate. |
| `cur_end` | uint63 | Inclusive current-read end coordinate. |
| `cur_len` | uint63 | Current-read length. |
| `ext_id` | signed int64 | Extension/target read id using Flye signed id orientation. |
| `ext_begin` | uint63 | Inclusive extension-read begin coordinate. |
| `ext_end` | uint63 | Inclusive extension-read end coordinate. |
| `ext_len` | uint63 | Extension-read length. |
| `score` | signed int64 | Flye chain score stored in `OverlapRange::score`. |
| `seq_divergence` | float | Flye `OverlapRange::seqDivergence` after divergence filtering or trimming. |

## Semantics

Rows are emitted after `OverlapDetector::getSeqOverlaps` finishes:

- candidate collection has completed;
- candidate hits have been sorted and chained;
- `overlapTest` has passed;
- primary-overlap selection has run;
- divergence filtering and bad-mapping trimming have run;
- `detectedOverlaps` is ready to return.

`cur_begin`, `cur_end`, `ext_begin`, and `ext_end` follow Flye's existing
inclusive coordinate convention. Therefore a range length is `end - begin`.

Signed ids encode strand orientation. Positive ids are forward reads; negative
ids are reverse-complement orientation.

## Ordering

The runtime dump preserves Flye's emitted order. For equality checks,
`tools/diff_overlap_dumps.py` canonicalizes rows by sorting on all fields in
the TSV order, with numeric comparison for integer fields and numeric comparison
for `seq_divergence`.

Canonical SHA-256 values are computed over normalized TSV text with
`seq_divergence` formatted by the validator.

## Failure Rules

A valid overlap-range-v1 file:

- is UTF-8 text;
- has no header;
- has exactly 10 fields per non-empty row;
- has at least one row;
- has non-zero signed ids;
- has coordinates satisfying `0 <= begin <= end < len`;
- has `cur_len > 0` and `ext_len > 0`;
- has finite non-negative `seq_divergence`;
- ends every row with LF.

## Non-Goals

This ABI does not define:

- raw candidate hits;
- k-mer match backtrace payloads;
- graph edges;
- polishing alignments;
- scientific equivalence tolerances for future approximate GPU divergence
  calculations.
