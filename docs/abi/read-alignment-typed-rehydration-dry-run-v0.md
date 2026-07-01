# Read Alignment Typed Rehydration Dry Run v0

Status: accepted in M5k

Introduced: M5k

Scope: Flye-side dry-run conversion of validated CUDA read-alignment worker TSV
output into GraphAlignment-shaped typed records before any graph mutation can
consume it.

## Purpose

`cuflye-read-alignment-typed-rehydration-dry-run-v0` is a representation-safety
contract. M5j proves that Flye can invoke the CUDA read-alignment replay worker,
validate worker output against CPU oracle TSV, and write graph guard metadata.
M5k adds the next boundary: validated worker rows must survive conversion back
toward Flye's `GraphAlignment` representation without losing ids, ranges,
scores, divergence, edge identity, or chain segment ordering.

The mode still does not replace Flye's `_readAlignments` vector and does not
feed CUDA output into graph mutation.

## Selector

The mode is disabled by default. It is enabled only when:

```text
CUFLYE_READ_ALIGNMENT_REHYDRATION_MODE=typed-graph-alignment-v0
```

Unsupported values fail closed before graph mutation. The positive dry-run
requires the M5j graph guard to be eligible, which means worker validation and
guard checks must pass first.

## Typed Representation

`typed-graph-alignment-v0` converts each `read-alignment-v1` worker row into a
Flye-side typed segment:

| Worker field | Flye-side type/check |
| --- | --- |
| `chain_id`, `segment_id` | non-negative signed integer, contiguous per chain |
| `read_id` | `FastaRecord::Id` |
| `read_begin`, `read_end`, `read_len` | checked `int32_t` range |
| `edge_id` | `FastaRecord::Id`, must resolve to `GraphEdge*` in current graph |
| `edge_seq_id` | `FastaRecord::Id` stored in `OverlapRange::extId` |
| `edge_begin`, `edge_end`, `edge_len` | checked `int32_t` range |
| `score` | checked `int32_t` |
| `seq_divergence` | finite `float`, matching Flye `OverlapRange` storage |

The typed segment contains an `EdgeAlignment` with an `OverlapRange` plus the
resolved `GraphEdge*`. The converted records are canonicalized back to
`read-alignment-v1` fields and compared with the CPU oracle TSV for the same
fixture.

## Generated File

When enabled, Flye writes:

```text
read-alignment-worker-rehydration.json
```

with schema:

```json
{
  "schema": "cuflye-read-alignment-typed-rehydration-dry-run-v0",
  "status": "passed",
  "mode": "typed-graph-alignment-v0",
  "typed_representation": "typed-graph-alignment-v0",
  "state": "not-consumed",
  "decision": "typed-graph-alignment-match-not-consumed",
  "eligible": true,
  "consumed": false,
  "not_consumed": true,
  "failed_closed": false,
  "graph_mutation_consumed_worker_output": false
}
```

`read-alignment-seam-summary.json` also records:

```json
{
  "read_alignment_rehydration_mode": "typed-graph-alignment-v0",
  "read_alignment_rehydration_json": "read-alignment-worker-rehydration.json",
  "read_alignment_rehydration_status": "passed",
  "read_alignment_rehydration_state": "not-consumed",
  "read_alignment_rehydration_decision": "typed-graph-alignment-match-not-consumed",
  "read_alignment_rehydration_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

## Required Checks

| Check | Meaning |
| --- | --- |
| `explicit_rehydration_mode` | The mode is explicitly `typed-graph-alignment-v0`. |
| `graph_guard_passed` | M5j graph guard reports `status=passed` and `eligible=true`. |
| `validation_passed` | Worker output validation passed. |
| `fixture_count_nonzero` | At least one replay fixture is selected. |
| `audit_metadata_available` | Rehydration audit JSON path is available. |

All required checks must pass before typed conversion is eligible.

## Negative Proof Fault

M5k allows one explicit proof-only fault:

```text
CUFLYE_READ_ALIGNMENT_REHYDRATION_PROOF_FAULT=drop-first-worker-record
```

This fault is disabled by default. It is used only to prove that a typed record
mismatch fails closed after worker validation and the M5j graph guard have
already passed.

## Failure Semantics

On any failed precondition, parse error, type conversion error, missing graph
edge, non-contiguous chain segment, record-count mismatch, or typed-record
mismatch, Flye writes `read-alignment-worker-rehydration.json`, writes
`read-alignment-seam-summary.json` with:

```json
{
  "status": "rehydration-failed-before-graph-mutation",
  "read_alignment_rehydration_status": "failed",
  "read_alignment_rehydration_state": "failed-closed",
  "read_alignment_rehydration_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and exits non-zero before graph mutation. There is no silent CPU fallback when
the seam and rehydration dry-run are explicitly enabled.

## M5k Benefit Assessment

In plain terms, M5k still does not make full Flye faster. Its value is
integration safety: CUDA read-alignment output must now fit Flye's typed
`GraphAlignment` shape and current repeat graph before any future milestone can
consider consuming it.
