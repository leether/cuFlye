# Read-to-Graph Full Query-Hit Raw-Overlap Rehydration Dry Run v0

Status: accepted in M6p

Introduced: M6p

Scope: Flye-side dry-run conversion of session-validated CUDA
full-query-hit raw-overlap TSV rows into typed `OverlapRange`-shaped records
before any graph mutation can consume worker output.

## Purpose

`cuflye-read-to-graph-full-query-hit-raw-overlap-rehydration-dry-run-v0` is a
representation-safety contract. M6n/M6o prove that a file-backed CUDA
full-query-hit worker session can emit raw-overlap rows whose canonical row key
matches the CPU oracle. M6p adds the next gate: after row-key parity passes,
Flye parses those rows back into checked Flye-side range/id fields and proves
that the typed representation canonicalizes back to the same row keys.

The mode still does not feed CUDA output into repeat-graph mutation.

## Selector

The mode is disabled by default. It is enabled only when:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_MODE=raw-overlap-vector-dry-run-v0
```

It requires:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE=full-query-hit-dry-run-v0
```

Unsupported values fail closed before graph mutation. A proof fault without the
rehydration mode also fails closed during configuration validation.

## Typed Representation

`raw-overlap-vector-dry-run-v0` converts each
`cuflye-read-to-graph-raw-overlap-v0` worker row into a narrow Flye-side record:

| Worker field | Flye-side type/check |
| --- | --- |
| `query_id` | signed integer preserved for the row-key gate |
| `source_order`, `raw_overlap_count`, `chain_input_count` | non-negative signed integers preserved for later gates |
| `read_id` | checked `FastaRecord::Id` |
| `read_begin`, `read_end`, `read_len` | checked `int32_t` range |
| `edge_seq_id` | checked `FastaRecord::Id` stored in `OverlapRange::extId` |
| `edge_begin`, `edge_end`, `edge_len` | checked `int32_t` range |
| `edge_id` | preserved raw field; `0` means not yet bound to a graph edge |
| `score` | checked `int32_t` |
| `seq_divergence` | finite `float`, matching `OverlapRange` storage |
| `passes_chain_input_filter` | `0` or `1` |

M6p deliberately does not resolve `edge_id=0` to `GraphEdge*`. Full-query-hit
raw-overlap rows are earlier than read-alignment object construction; the graph
edge identity gate belongs to a later consumption task.

## Generated Files

When enabled, Flye writes:

```text
full-query-hit-worker-raw-overlap-rehydration.json
```

with schema:

```json
{
  "schema": "cuflye-read-to-graph-full-query-hit-raw-overlap-rehydration-dry-run-v0",
  "status": "passed",
  "mode": "raw-overlap-vector-dry-run-v0",
  "typed_representation": "raw-overlap-vector-dry-run-v0",
  "state": "not-consumed",
  "decision": "raw-overlap-vector-match-not-consumed",
  "eligible": true,
  "consumed": false,
  "not_consumed": true,
  "failed_closed": false,
  "graph_mutation_consumed_worker_output": false
}
```

`full-query-hit-worker-dry-run.json` also records:

```json
{
  "raw_overlap_rehydration_status": "passed",
  "raw_overlap_rehydration_eligible": true,
  "raw_overlap_rehydrated_records": 36,
  "graph_mutation_consumed_worker_output": false
}
```

## Required Checks

| Check | Meaning |
| --- | --- |
| `explicit_rehydration_mode` | The mode is explicitly `raw-overlap-vector-dry-run-v0`. |
| `worker_row_key_parity_passed` | Worker row-key diff already passed. |
| `worker_output_readable` | Worker raw-overlap TSV is readable. |
| `audit_metadata_available` | Rehydration audit JSON path is available. |
| `graph_not_mutated` | Worker output has not reached graph mutation. |
| `rehydrated_count_matches_worker` | Rehydrated record count equals worker row count. |
| `typed_row_keys_match_worker` | Rehydrated typed rows canonicalize to the validated worker row keys. |

## Negative Proof Fault

M6p allows one explicit proof-only fault:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_PROOF_FAULT=drop-first-rehydrated-record
```

The fault is applied after worker row-key parity has passed. It removes one
rehydrated record so the typed row-key diff fails, proving this gate fails
closed independently of the earlier row-key gate.

## Failure Semantics

On any failed precondition, parse error, type conversion error, record-count
mismatch, or typed row-key mismatch, Flye writes
`full-query-hit-worker-raw-overlap-rehydration.json`, writes
`full-query-hit-worker-dry-run.json` with:

```json
{
  "status": "rehydration-failed-before-graph-mutation",
  "raw_overlap_rehydration_status": "failed",
  "raw_overlap_rehydration_failed_closed": true,
  "graph_mutation_consumed_worker_output": false
}
```

and exits non-zero before graph mutation. There is no silent CPU fallback when
the seam and rehydration dry-run are explicitly enabled.

## M6p Benefit Assessment

In plain terms, M6p still does not make full Flye faster. Its value is
integration safety: CUDA full-query-hit worker output can now cross one more
Flye-side boundary, survive typed parsing, and prove it is still not consumed by
graph mutation unless a later task adds a separate consumption gate.
