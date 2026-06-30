# Overlap Rehydration Dry Run v0

Status: proposed for M4p

Introduced: M4p

Scope: Flye-side dry-run conversion of validated CUDA overlap worker TSV output
into a typed overlap vector before any graph mutation can consume it.

## Purpose

`cuflye-overlap-rehydration-dry-run-v0` is a representation-safety contract.
M4l validates worker files against disk oracles, M4m shadow-compares worker
files against CPU records captured in memory, and M4o proves graph-consumption
preconditions. M4p adds the next boundary: worker TSV records must survive a
Flye-side typed conversion without losing ids, ranges, scores, or divergence.

The mode still does not feed CUDA output into graph construction.

## Selector

The mode is disabled by default. It is enabled only when:

```text
CUFLYE_OVERLAP_REHYDRATION_MODE=typed-overlap-v0
```

Unsupported values fail closed before graph mutation.

The positive dry-run requires the M4o graph-consumption guard to be eligible.
This means validation, shadow comparison, and guard checks must all pass first.

## Typed Representation

`typed-overlap-v0` converts each `overlap-range-v1` worker row into a Flye-side
typed record:

| Field | Type |
| --- | --- |
| `cur_id` | `FastaRecord::Id` |
| `cur_begin`, `cur_end`, `cur_len` | checked `int32_t` |
| `ext_id` | `FastaRecord::Id` |
| `ext_begin`, `ext_end`, `ext_len` | checked `int32_t` |
| `score` | checked `int32_t` |
| `seq_divergence` | `double` |

The conversion checks that signed ids and numeric fields fit Flye's in-memory
types. It then canonicalizes the typed vector back to `overlap-range-v1` fields
and compares it with CPU records captured in memory.

## Generated File

When enabled, Flye writes:

```text
worker-rehydration.json
```

with schema:

```json
{
  "schema": "cuflye-overlap-rehydration-dry-run-v0",
  "status": "passed",
  "mode": "typed-overlap-v0",
  "typed_representation": "typed-overlap-v0",
  "state": "not-consumed",
  "decision": "typed-vector-match-not-consumed",
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
  "overlap_rehydration_mode": "typed-overlap-v0",
  "overlap_rehydration_json": "worker-rehydration.json",
  "overlap_rehydration_status": "passed",
  "overlap_rehydration_state": "not-consumed",
  "overlap_rehydration_decision": "typed-vector-match-not-consumed",
  "overlap_rehydration_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

## Required Checks

| Check | Meaning |
| --- | --- |
| `explicit_rehydration_mode` | The mode is explicitly `typed-overlap-v0`. |
| `graph_guard_passed` | M4o graph guard reports `status=passed` and `eligible=true`. |
| `validation_passed` | Worker output validation passed. |
| `shadow_passed` | In-memory shadow comparison passed. |
| `fixture_count_matches_request` | Captured fixture count equals `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`. |
| `audit_metadata_available` | Rehydration audit JSON path is available. |

All required checks must pass before typed conversion is eligible.

## Negative Proof Fault

M4p allows one explicit proof-only fault:

```text
CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT=drop-first-worker-record
```

This fault is disabled by default. It is used only to prove that a typed-vector
mismatch fails closed after validation, shadow comparison, and the M4o guard
have already passed.

## Failure Semantics

On any failed precondition, type conversion error, record-count mismatch, or
typed-vector mismatch, Flye writes `worker-rehydration.json`, writes
`seam-summary.json` with:

```json
{
  "status": "rehydration-failed-before-graph-mutation",
  "overlap_rehydration_status": "failed",
  "overlap_rehydration_state": "failed-closed",
  "overlap_rehydration_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and exits non-zero before graph mutation.

There is no silent CPU fallback when the seam and rehydration dry-run are
explicitly enabled.

## M4p Benefit Assessment

In plain terms, this still does not make Flye faster. Its value is lowering the
risk of the future graph-consumption milestone: CUDA output is now forced
through a typed Flye-side representation check before it can ever be considered
for graph construction.
