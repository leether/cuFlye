# Overlap Graph Consumption Guard v0

Status: accepted in M4o

Introduced: M4o

Scope: Flye-side dry-run guard metadata for any future path that might consume
CUDA overlap worker output in graph mutation.

## Purpose

`cuflye-overlap-graph-consumption-guard-v0` is a safety contract, not a graph
mutation implementation. It records whether CUDA overlap worker output has
passed all preconditions required to become eligible for future graph
consumption, while still keeping graph mutation on the CPU path.

The guard exists because M4l, M4m, and M4n prove increasingly strong overlap
worker correctness boundaries, but none of them defines how Flye would safely
move from "validated and shadow-matched" to "may affect graph mutation".

## Selector

The guard is disabled by default. It is enabled only when:

```text
CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE=dry-run-v0
```

Unsupported values fail closed before graph mutation.

`dry-run-v0` never consumes worker output. It only writes guard metadata after
the existing validation and shadow gates run.

## Required Precondition Checks

The guard writes one required check per precondition:

| Check | Meaning |
| --- | --- |
| `explicit_guard_mode` | The mode is explicitly `dry-run-v0`. |
| `validation_passed` | `worker-validation.json` reports `status=passed` and `worker_output_consumption_eligible=true`. |
| `shadow_mode_selected` | `CUFLYE_OVERLAP_WORKER_SHADOW_MODE=canonical-overlap-v0` is enabled. |
| `shadow_passed` | `worker-shadow.json` reports `status=passed` and `shadow_consumption_eligible=true`. |
| `fixture_count_matches_request` | Captured fixture count equals `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`. |
| `audit_metadata_available` | The guard audit JSON path is available. |

All required checks must pass before guard eligibility can be `eligible`.

## Generated File

When enabled, Flye writes:

```text
worker-graph-consumption-guard.json
```

with schema:

```json
{
  "schema": "cuflye-overlap-graph-consumption-guard-v0",
  "status": "passed",
  "mode": "dry-run-v0",
  "guard_eligibility": "eligible",
  "graph_consumption_state": "not-consumed",
  "decision": "dry-run-not-consumed",
  "eligible": true,
  "consumed": false,
  "not_consumed": true,
  "failed_closed": false,
  "graph_mutation_consumed_worker_output": false,
  "checks": [
    {
      "name": "validation_passed",
      "required": true,
      "passed": true,
      "detail": "worker output validation must pass"
    }
  ]
}
```

`seam-summary.json` also includes:

```json
{
  "graph_consumption_mode": "dry-run-v0",
  "graph_guard_json": "worker-graph-consumption-guard.json",
  "graph_guard_status": "passed",
  "graph_guard_eligibility": "eligible",
  "graph_consumption_state": "not-consumed",
  "graph_consumption_decision": "dry-run-not-consumed",
  "graph_consumption_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

## States

| State | Meaning |
| --- | --- |
| `eligible` | All dry-run preconditions passed. Future graph-consumption work may use this as the minimum entry condition. |
| `not-consumed` | Worker output was not used for graph mutation. This is the only successful M4o state. |
| `failed-closed` | At least one required precondition failed, and Flye stopped before graph mutation. |
| `consumed` | Reserved for a later milestone. M4o must never write `consumed=true`. |

## Failure Semantics

If dry-run mode is enabled and any required check fails, Flye writes
`worker-graph-consumption-guard.json`, writes `seam-summary.json` with:

```json
{
  "status": "guard-failed-before-graph-mutation",
  "graph_guard_status": "failed",
  "graph_consumption_state": "failed-closed",
  "graph_consumption_eligible": false,
  "graph_mutation_consumed_worker_output": false
}
```

and exits non-zero before graph mutation.

There is no silent CPU fallback when the seam and guard are explicitly enabled.

## M4o Benefit Assessment

In plain terms, this guard does not make Flye faster. Its value is reducing the
risk of the next step: before GPU overlap output can affect graph construction,
the code now has a named, auditable, fail-closed contract that says exactly
which preconditions must be true and records why output was or was not eligible.
