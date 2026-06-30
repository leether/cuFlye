# cuFlye Overlap Replay Fixture v0

Status: active

Introduced: M4b

Scope: bounded CPU replay fixtures for Flye
`OverlapDetector::getSeqOverlaps` after candidate collection and before future
CUDA overlap chaining.

## Purpose

`overlap-replay-fixture-v0` captures the minimum input needed to replay Flye's
candidate-to-overlap chaining for one query read:

- sorted candidate hits;
- repetitive or filtered query positions used by the divergence estimator;
- target read lengths;
- chain/filter parameters;
- an `overlap-range-v1` oracle for the same query.

The fixture exists to separate semantic replay from full Flye execution before
any CUDA chain DP is introduced.

## Directory Layout

Each fixture is a directory named by query id, for example:

```text
query_1/
  manifest.json
  candidates.tsv
  filtered-positions.tsv
  targets.tsv
  oracle.overlaps.tsv
```

## Files

`manifest.json` uses schema `cuflye-overlap-replay-fixture-v0` and records:

- `query_id` and `query_length`;
- file names for the TSV payloads;
- record counts for sanity checks;
- chain parameters from the active Flye run.

`candidates.tsv` uses `candidate-record-v1` rows for exactly one query. Raw row
order is the order Flye had after sorting by target `FastaRecord::Id` and query
position.

`filtered-positions.tsv` has one non-negative query coordinate per line. These
positions are subtracted from the k-mer divergence estimator denominator.

`targets.tsv` has two tab-separated fields:

```text
target_id<TAB>target_length
```

`oracle.overlaps.tsv` is an `overlap-range-v1` file for the same query after
Flye's CPU chaining, primary-overlap filtering, and divergence filtering.

## Supported M4b Shape

The first replay harness intentionally supports only the non-base-alignment
shape:

- `nucl_alignment=false`;
- `partition_bad_mappings=false`;
- `keep_alignment=false`.

Those constraints keep M4b focused on k-mer chain DP, overlap tests, primary
overlap selection, and k-mer-estimated divergence. Fixtures requiring base-level
alignment or bad-mapping trimming must fail closed until a later Task Card adds
that semantic unit.

## Replay Gate

A replay run passes when:

- `tools/replay_overlap_chains.py` exits zero;
- its output validates as `overlap-range-v1`;
- canonical diff against `oracle.overlaps.tsv` reports `match`.

The replay output is not allowed to feed Flye graph logic. It is a proof
boundary for future CUDA chain DP only.

## Non-Goals

This ABI does not define:

- a CUDA kernel interface;
- base-level alignment replay;
- bad-mapping trim replay;
- graph construction;
- end-to-end Flye speedup.
