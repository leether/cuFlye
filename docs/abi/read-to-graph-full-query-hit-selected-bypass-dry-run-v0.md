# ABI: Read-to-Graph Full Query-Hit Selected Bypass Dry-Run v0

Status: proposed

Created: 2026-07-01

## Purpose

`cuflye-read-to-graph-full-query-hit-selected-bypass-dry-run-v0` is an opt-in
no-mutation dry-run for the CUDA full-query-hit worker path.

It runs after M6w selected bypass-plan has proved which rows are safe selected
bypass candidates and which rows remain CPU-owned. This ABI marks the selected
rows as actually bypassed in dry-run state, preserves the CPU-owned residual
rows, writes a merged accounting ledger for all CPU raw-overlap rows, and still
stops before Flye graph mutation.

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
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_MODE=selected-bypass-dry-run-v0
```

Negative proof injection:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_BYPASS_DRY_RUN_PROOF_FAULT=drop-first-selected-bypass-row
```

## Output

Flye writes:

```text
full-query-hit-worker-selected-bypass-dry-run.json
```

The worker dry-run audit also mirrors the status and row counts:

```json
{
  "raw_overlap_selected_bypass_dry_run_json": ".../full-query-hit-worker-selected-bypass-dry-run.json",
  "raw_overlap_selected_bypass_dry_run_status": "passed",
  "raw_overlap_selected_bypass_dry_run_bypassed_rows": 8,
  "raw_overlap_selected_bypass_dry_run_cpu_owned_rows": 28,
  "raw_overlap_selected_bypass_dry_run_merged_rows": 36
}
```

## Standalone JSON Schema

Top-level fields:

| Field | Meaning |
| --- | --- |
| `schema` | Always `cuflye-read-to-graph-full-query-hit-selected-bypass-dry-run-v0`. |
| `status` | `passed`, `failed`, or `not-requested`. |
| `mode` | The requested mode string. |
| `proof_fault` | Empty or `drop-first-selected-bypass-row`. |
| `proof_fault_applied` | Whether the negative proof fault changed the selected bypass payload. |
| `state` | `not-consumed` or `failed-closed`. |
| `decision` | Human-readable final gate decision. |
| `bypass_plan_status` | M6w bypass-plan status. |
| `eligible` | Whether selected bypass dry-run passed all checks. |
| `consumed` | Always false in v0. |
| `not_consumed` | True only when the dry-run was not consumed by graph mutation. |
| `failed_closed` | True when any required check failed. |
| `total_cpu_raw_overlap_rows` | CPU oracle raw-overlap rows for the selected source pack. |
| `bypass_plan_ledger_rows` | M6w selected bypass ledger rows. |
| `bypass_plan_cpu_owned_rows` | M6w CPU-owned residual rows. |
| `selected_bypass_payload_rows` | Selected rows present in the dry-run bypass payload. |
| `selected_bypassed_rows` | Rows marked actually bypassed in dry-run state. |
| `cpu_owned_residual_rows` | Rows preserved as CPU-owned residuals. |
| `merged_ledger_rows` | Rows in the merged bypass-plus-CPU-owned ledger. |
| `selected_bypass_missing_rows` | Selected rows missing from a corrupted bypass payload. |
| `selected_bypass_unexpected_rows` | Unexpected rows added to the bypass payload. |
| `selected_bypass_rows` | Deterministic selected bypass dry-run rows. |
| `cpu_owned_rows` | Deterministic CPU-owned residual rows from M6w. |
| `merged_ledger` | Deterministic merged ledger over all CPU raw-overlap rows. |
| `selected_bypass_row_key_diff` | Canonical row-key diff between the M6w-equivalent selected handoff and selected bypass payload. |

Each ledger entry contains:

| Field | Meaning |
| --- | --- |
| `order_index` | Deterministic row order within that ledger. |
| `query_id` | Flye query read id. |
| `source_order` | Original full-query-hit source-pack row order. |
| `edge_id` | Resolved edge id, or zero when unsupported. |
| `read_id` | `OverlapRange.curId`. |
| `edge_seq_id` | `OverlapRange.extId`. |
| `decision` | `selected-bypassed-dry-run`, `cpu-owned`, or `selected-bypass-payload-missing`. |
| `reason` | Why the row is in that ledger. |

## Invariants

- The mode cannot run unless M6p through M6w are enabled.
- M6w selected bypass-plan must pass first.
- Positive proof requires nonzero `selected_bypassed_rows`.
- Positive proof requires selected bypass dry-run rows to equal M6w bypass
  ledger rows.
- Positive proof requires selected bypass row keys and order to match the
  M6w-equivalent selected handoff row keys.
- Positive proof preserves CPU-owned residual rows from M6w.
- Positive proof writes a merged ledger accounting for all CPU raw-overlap rows.
- Positive proof requires zero missing or unexpected selected bypass rows.
- The selected bypass dry-run is not consumed by graph mutation in v0.
- Negative proof with `drop-first-selected-bypass-row` must fail closed before
  graph mutation.

## Non-Claims

This ABI does not prove default GPU mode, real graph mutation, repeat graph
simplification changes, whole-Flye speedup, or independent GPU calculation of
chain-input filtering and edge identity.
