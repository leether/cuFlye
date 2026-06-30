# OverlapRange Object Rehydration Dry Run v0

Status: proposed for M4q

Introduced: M4q

Scope: Flye-side dry-run conversion of validated typed overlap records into
actual Flye `OverlapRange` objects before any graph mutation can consume them.

## Purpose

`cuflye-overlap-range-object-rehydration-dry-run-v0` is the next
representation-safety contract after M4p. M4p proves that worker
`overlap-range-v1` rows can survive a typed Flye-side conversion. M4q proves
that those typed records can also become upstream Flye `OverlapRange` objects
without changing the canonical overlap vector.

The mode still does not feed CUDA output into graph construction.

## Selector

The mode is disabled by default. It is enabled only when:

```text
CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE=overlap-range-object-v0
```

Unsupported values fail closed before graph mutation.

The positive dry-run requires M4p typed rehydration to pass first.

## Object Representation

`overlap-range-object-v0` converts each typed overlap record into an
`OverlapRange` object:

| Field | Source |
| --- | --- |
| `curId`, `extId` | Typed `FastaRecord::Id` values. |
| `curBegin`, `curEnd`, `curLen` | Typed current-read coordinates. |
| `extBegin`, `extEnd`, `extLen` | Typed extension-read coordinates. |
| `score` | Typed chain score. |
| `seqDivergence` | Typed divergence converted to Flye `float`. |
| `kmerMatches` | Left unset as `nullptr` in M4q. |

The object vector is canonicalized back to `overlap-range-v1` and compared with
CPU overlap records captured in memory.

## Generated File

When enabled, Flye writes:

```text
worker-object-rehydration.json
```

with schema:

```json
{
  "schema": "cuflye-overlap-range-object-rehydration-dry-run-v0",
  "status": "passed",
  "mode": "overlap-range-object-v0",
  "object_representation": "overlap-range-object-v0",
  "state": "not-consumed",
  "decision": "overlap-range-object-match-not-consumed",
  "eligible": true,
  "consumed": false,
  "not_consumed": true,
  "failed_closed": false,
  "graph_mutation_consumed_worker_output": false
}
```

`seam-summary.json` also includes:

```json
{
  "overlap_object_rehydration_mode": "overlap-range-object-v0",
  "overlap_object_rehydration_json": "worker-object-rehydration.json",
  "overlap_object_rehydration_status": "passed",
  "overlap_object_rehydration_state": "not-consumed",
  "overlap_object_rehydration_decision": "overlap-range-object-match-not-consumed",
  "overlap_object_rehydration_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

## Required Checks

| Check | Meaning |
| --- | --- |
| `explicit_object_rehydration_mode` | The mode is explicitly `overlap-range-object-v0`. |
| `typed_rehydration_passed` | M4p typed rehydration reports `status=passed` and `eligible=true`. |
| `fixture_count_matches_request` | Captured fixture count equals `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`. |
| `audit_metadata_available` | Object rehydration audit JSON path is available. |

All required checks must pass before object conversion is eligible.

## Negative Proof Fault

M4q allows one explicit proof-only fault:

```text
CUFLYE_OVERLAP_OBJECT_REHYDRATION_PROOF_FAULT=drop-first-overlap-range
```

This fault is disabled by default. It is used only to prove that an
`OverlapRange` object-vector mismatch fails closed after M4p typed rehydration
has already passed.

## Failure Semantics

On any failed precondition, conversion error, record-count mismatch, or
object-vector mismatch, Flye writes `worker-object-rehydration.json`, writes
`seam-summary.json` with:

```json
{
  "status": "object-rehydration-failed-before-graph-mutation",
  "overlap_object_rehydration_status": "failed",
  "overlap_object_rehydration_state": "failed-closed",
  "overlap_object_rehydration_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and exits non-zero before graph mutation.

There is no silent CPU fallback when the seam and object rehydration dry-run are
explicitly enabled.

## M4q Benefit Assessment

In plain terms, this still does not make Flye faster. Its value is lowering the
risk of future graph consumption by proving CUDA overlap output can be expressed
as the real Flye `OverlapRange` object vector and still match CPU records before
graph construction can consider it.
