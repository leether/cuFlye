# ABI: Read-to-Graph Full Query-Hit Selected Bypass Plan v0

Status: proposed

Created: 2026-07-01

## Purpose

`cuflye-read-to-graph-full-query-hit-selected-bypass-plan-v0` is an opt-in
no-mutation audit for the CUDA full-query-hit worker path.

It runs after M6v verified substitution has proved that the CUDA-derived
would-substitute ledger matches the selected CPU handoff rows by row key and
order. The bypass-plan audit records which selected rows are eligible for a
future CPU handoff bypass, records the remaining raw-overlap rows as CPU-owned,
and still prevents the plan from being consumed by Flye graph mutation.

## Activation

The mode is disabled by default.

Enable it only with all prior full-query-hit gates:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE=dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_MODE=raw-overlap-vector-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_MODE=raw-overlap-chain-input-shadow-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_MODE=graph-edge-binding-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_MODE=object-vector-smoke-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_MODE=substitution-guard-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_MODE=verified-substitution-smoke-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_MODE=selected-bypass-plan-v0
```

Negative proof injection:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_PLAN_PROOF_FAULT=drop-first-bypass-ledger-row
```

## Output

Flye writes:

```text
full-query-hit-worker-selected-bypass-plan.json
```

The worker dry-run audit also mirrors the status and row counts:

```json
{
  "raw_overlap_selected_bypass_plan_json": ".../full-query-hit-worker-selected-bypass-plan.json",
  "raw_overlap_selected_bypass_plan_status": "passed",
  "raw_overlap_selected_bypass_plan_eligible_rows": 8,
  "raw_overlap_selected_bypass_plan_ledger_rows": 8,
  "raw_overlap_selected_bypass_plan_cpu_owned_rows": 28
}
```

## Standalone JSON Schema

Top-level fields:

| Field | Meaning |
| --- | --- |
| `schema` | Always `cuflye-read-to-graph-full-query-hit-selected-bypass-plan-v0`. |
| `status` | `passed`, `failed`, or `not-requested`. |
| `mode` | The requested mode string. |
| `proof_fault` | Empty or `drop-first-bypass-ledger-row`. |
| `proof_fault_applied` | Whether the negative proof fault changed the bypass ledger. |
| `state` | `not-consumed` or `failed-closed`. |
| `decision` | Human-readable final gate decision. |
| `verified_substitution_status` | M6v verified-substitution status. |
| `eligible` | Whether the selected bypass plan passed all checks. |
| `consumed` | Always false in v0. |
| `not_consumed` | True only when the plan was not consumed by graph mutation. |
| `failed_closed` | True when any required check failed. |
| `total_cpu_raw_overlap_rows` | CPU oracle raw-overlap rows for the selected source pack. |
| `verified_substitution_ledger_rows` | M6v substitution ledger rows. |
| `selected_cpu_handoff_rows` | CPU oracle selected handoff rows. |
| `selected_bypass_eligible_rows` | Rows eligible for future CPU handoff bypass. |
| `selected_bypass_ledger_rows` | Rows written to the bypass ledger. |
| `cpu_owned_residual_rows` | Raw-overlap rows kept CPU-owned. |
| `bypass_ledger` | Deterministic selected bypass rows. |
| `cpu_owned_rows` | Deterministic CPU-owned residual rows with reasons. |
| `bypass_row_key_diff` | Canonical CPU selected handoff vs bypass ledger row-key diff. |

Each `bypass_ledger` or `cpu_owned_rows` entry contains:

| Field | Meaning |
| --- | --- |
| `order_index` | Deterministic row order within that ledger. |
| `query_id` | Flye query read id. |
| `source_order` | Original full-query-hit source-pack row order. |
| `edge_id` | Resolved edge id, or zero when unsupported. |
| `read_id` | `OverlapRange.curId`. |
| `edge_seq_id` | `OverlapRange.extId`. |
| `decision` | `selected-bypass-eligible` or `cpu-owned`. |
| `reason` | Why the row is in that ledger. |

## Invariants

- The mode cannot run unless M6p, M6q, M6s, M6t, M6u, and M6v are enabled.
- M6v verified substitution must pass first.
- Positive proof requires nonzero `selected_bypass_eligible_rows`.
- Positive proof requires selected bypass rows to equal M6v substitution ledger
  rows.
- Positive proof requires bypass row keys and order to match selected CPU
  handoff rows.
- Positive proof explicitly records CPU-owned residual rows.
- Bypass rows plus CPU-owned residual rows must account for all selected source
  pack CPU raw-overlap rows.
- The bypass plan is not consumed by graph mutation in v0.
- Negative proof with `drop-first-bypass-ledger-row` must fail closed before
  graph mutation.

## Non-Claims

This ABI does not prove default GPU mode, real CPU bypass, real Flye graph
mutation, repeat graph simplification changes, whole-Flye speedup, or
independent GPU calculation of chain-input filtering and edge identity.
