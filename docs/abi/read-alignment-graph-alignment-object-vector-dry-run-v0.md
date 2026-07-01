# Read Alignment GraphAlignment Object-Vector Dry Run v0

Status: accepted for M5l

Introduced: M5l

Scope: Flye-side dry-run conversion of validated CUDA read-alignment worker TSV
output into a shadow `std::vector<GraphAlignment>` object vector before any
graph mutation can consume it.

## Purpose

`cuflye-read-alignment-graph-alignment-object-vector-dry-run-v0` is the
representation-safety contract after M5k. M5k proves that worker TSV rows can
survive checked typed conversion into GraphAlignment-shaped segments. M5l proves
that those typed segments can also be grouped into an actual Flye
`std::vector<GraphAlignment>` shadow object vector and still match the CPU
`_readAlignments` slice for the same read ids.

The mode still does not replace Flye's `_readAlignments` vector and does not
feed CUDA output into graph mutation.

## Selector

The mode is disabled by default. It is enabled only when:

```text
CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_MODE=graph-alignment-object-vector-v0
```

Unsupported values fail closed before graph mutation. The positive dry-run
requires M5k typed rehydration to pass first:

```text
CUFLYE_READ_ALIGNMENT_REHYDRATION_MODE=typed-graph-alignment-v0
```

## Object Representation

`graph-alignment-object-vector-v0` groups M5k typed segments into:

```cpp
std::vector<GraphAlignment>
```

where each `GraphAlignment` is a `std::vector<EdgeAlignment>`. Every
`EdgeAlignment` contains:

| Field | Source |
| --- | --- |
| `OverlapRange::curId` | typed read `FastaRecord::Id` |
| `OverlapRange::curBegin/curEnd/curLen` | checked typed read coordinates |
| `OverlapRange::extId` | typed edge-sequence `FastaRecord::Id` |
| `OverlapRange::extBegin/extEnd/extLen` | checked typed edge coordinates |
| `OverlapRange::score` | checked typed score |
| `OverlapRange::seqDivergence` | typed divergence stored as Flye `float` |
| `EdgeAlignment::edge` | `GraphEdge*` resolved from current `RepeatGraph` |

M5l compares the shadow object vector against a CPU slice taken from
`_readAlignments`, selecting chains whose first segment read id matches the
fixture query id. Both object vectors are canonicalized to `read-alignment-v1`
records with local chain ids before comparison.

## Generated File

When enabled, Flye writes:

```text
read-alignment-worker-object-rehydration.json
```

with schema:

```json
{
  "schema": "cuflye-read-alignment-graph-alignment-object-vector-dry-run-v0",
  "status": "passed",
  "mode": "graph-alignment-object-vector-v0",
  "object_representation": "graph-alignment-object-vector-v0",
  "state": "not-consumed",
  "decision": "graph-alignment-object-vector-match-not-consumed",
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
  "read_alignment_object_rehydration_mode": "graph-alignment-object-vector-v0",
  "read_alignment_object_rehydration_json": "read-alignment-worker-object-rehydration.json",
  "read_alignment_object_rehydration_status": "passed",
  "read_alignment_object_rehydration_state": "not-consumed",
  "read_alignment_object_rehydration_decision": "graph-alignment-object-vector-match-not-consumed",
  "read_alignment_object_rehydration_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

## Required Checks

| Check | Meaning |
| --- | --- |
| `explicit_object_rehydration_mode` | The mode is explicitly `graph-alignment-object-vector-v0`. |
| `typed_rehydration_passed` | M5k typed rehydration reports `status=passed` and `eligible=true`. |
| `fixture_count_nonzero` | At least one replay fixture is selected. |
| `audit_metadata_available` | Object-vector rehydration audit JSON path is available. |

All required checks must pass before object-vector conversion is eligible.

## Negative Proof Fault

M5l allows one explicit proof-only fault:

```text
CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_PROOF_FAULT=drop-first-graph-alignment-chain
```

This fault is disabled by default. It is used only to prove that a shadow
`GraphAlignment` object-vector mismatch fails closed after M5k typed
rehydration has already passed.

## Failure Semantics

On any failed precondition, conversion error, missing CPU `_readAlignments`
slice, record-count mismatch, or object-vector mismatch, Flye writes
`read-alignment-worker-object-rehydration.json`, writes
`read-alignment-seam-summary.json` with:

```json
{
  "status": "object-rehydration-failed-before-graph-mutation",
  "read_alignment_object_rehydration_status": "failed",
  "read_alignment_object_rehydration_state": "failed-closed",
  "read_alignment_object_rehydration_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and exits non-zero before graph mutation. There is no silent CPU fallback when
the seam and object-vector dry-run are explicitly enabled.

## M5l Benefit Assessment

In plain terms, M5l still does not make full Flye faster. Its value is lowering
the risk of future consumption: CUDA read-alignment output must now match Flye's
real `GraphAlignment` object-vector shape and the CPU `_readAlignments` slice
before any later milestone can consider replacing that slice.
