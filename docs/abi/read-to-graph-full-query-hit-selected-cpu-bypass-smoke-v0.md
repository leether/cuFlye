# ABI: Read-to-Graph Full Query-Hit Selected CPU-Bypass Smoke v0

Status: proposed

Created: 2026-07-01

## Purpose

`cuflye-read-to-graph-full-query-hit-selected-cpu-bypass-smoke-v0` is an
opt-in no-mutation smoke for the CUDA full-query-hit worker path.

It runs after M6x selected bypass dry-run has proved that selected rows can be
marked as bypassed in dry-run state. This ABI records selected CPU handoff rows
as skipped, records CUDA-derived rows as the selected handoff supplier,
preserves CPU-owned residual rows, writes a final merged smoke ledger for all
CPU raw-overlap rows, and still stops before Flye graph mutation.

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
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_MODE=selected-cpu-bypass-smoke-v0
```

Negative proof injection:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_CPU_BYPASS_SMOKE_PROOF_FAULT=leak-first-skipped-cpu-row
```

## Output

Flye writes:

```text
full-query-hit-worker-selected-cpu-bypass-smoke.json
```

The worker dry-run audit also mirrors the status and row counts:

```json
{
  "raw_overlap_selected_cpu_bypass_smoke_json": ".../full-query-hit-worker-selected-cpu-bypass-smoke.json",
  "raw_overlap_selected_cpu_bypass_smoke_status": "passed",
  "raw_overlap_selected_cpu_bypass_smoke_skipped_rows": 8,
  "raw_overlap_selected_cpu_bypass_smoke_supplied_rows": 8,
  "raw_overlap_selected_cpu_bypass_smoke_merged_rows": 36
}
```

## Standalone JSON Schema

Top-level fields:

| Field | Meaning |
| --- | --- |
| `schema` | Always `cuflye-read-to-graph-full-query-hit-selected-cpu-bypass-smoke-v0`. |
| `status` | `passed`, `failed`, or `not-requested`. |
| `mode` | The requested mode string. |
| `proof_fault` | Empty or `leak-first-skipped-cpu-row`. |
| `proof_fault_applied` | Whether the negative proof fault changed the smoke ledger. |
| `state` | `not-consumed` or `failed-closed`. |
| `decision` | Human-readable final gate decision. |
| `selected_bypass_dry_run_status` | M6x selected bypass dry-run status. |
| `eligible` | Whether selected CPU-bypass smoke passed all checks. |
| `consumed` | Always false in v0. |
| `not_consumed` | True only when the smoke was not consumed by graph mutation. |
| `failed_closed` | True when any required check failed. |
| `total_cpu_raw_overlap_rows` | CPU oracle raw-overlap rows for the selected source pack. |
| `selected_cpu_handoff_rows` | CPU-selected handoff rows being skipped. |
| `skipped_cpu_selected_rows` | Rows explicitly marked as skipped on the CPU-selected handoff. |
| `cuda_supplied_selected_rows` | CUDA-derived rows supplying the selected handoff. |
| `cpu_owned_residual_rows` | Rows preserved as CPU-owned residuals. |
| `final_merged_ledger_rows` | Rows in the final merged smoke ledger. |
| `final_cuda_supplied_rows` | CUDA-supplied selected rows present in the final merged ledger. |
| `leaked_selected_cpu_rows` | Skipped selected CPU rows that leaked back into CPU-owned path. |
| `missing_cuda_supplied_rows` | Skipped selected CPU rows missing a CUDA supplier. |
| `unexpected_cuda_supplied_rows` | Unexpected rows added to the CUDA supplier ledger. |
| `skipped_cpu_selected_rows_ledger` | Deterministic rows skipped from CPU-selected handoff. |
| `cuda_supplied_rows` | Deterministic CUDA-derived selected supplier rows. |
| `cpu_owned_rows` | Deterministic CPU-owned residual rows. |
| `final_merged_ledger` | Deterministic final smoke ledger over all CPU raw-overlap rows. |
| `cuda_supplied_row_key_diff` | Canonical selected CPU handoff vs CUDA supplier row-key diff. |
| `final_merged_row_key_diff` | Canonical CPU oracle vs final merged ledger row-key diff. |

Each ledger entry contains:

| Field | Meaning |
| --- | --- |
| `order_index` | Deterministic row order within that ledger. |
| `query_id` | Flye query read id. |
| `source_order` | Original full-query-hit source-pack row order. |
| `edge_id` | Resolved edge id, or zero when unsupported. |
| `read_id` | `OverlapRange.curId`. |
| `edge_seq_id` | `OverlapRange.extId`. |
| `decision` | One of `selected-cpu-handoff-skipped`, `cuda-supplied-selected-bypass`, `cpu-owned`, `cpu-owned-selected-leak`, or `selected-cpu-skip-without-cuda-supply`. |
| `reason` | Why the row is in that ledger. |

## Invariants

- The mode cannot run unless M6p through M6x are enabled.
- M6x selected bypass dry-run must pass first.
- Positive proof requires nonzero skipped selected CPU rows.
- Positive proof requires CUDA-supplied selected rows to equal skipped selected
  CPU rows.
- Positive proof requires CUDA-supplied row keys and order to match skipped
  selected CPU rows.
- Positive proof preserves CPU-owned residual rows from M6x.
- Positive proof writes a final merged ledger accounting for all CPU raw-overlap
  rows.
- Positive proof requires final merged row keys and order to match the CPU
  oracle.
- Positive proof requires zero leaked selected CPU rows, zero missing CUDA
  suppliers, and zero unexpected CUDA supplier rows.
- The selected CPU-bypass smoke is not consumed by graph mutation in v0.
- Negative proof with `leak-first-skipped-cpu-row` must fail closed before graph
  mutation.

## Non-Claims

This ABI does not prove default GPU mode, real graph mutation, repeat graph
simplification changes, whole-Flye speedup, or independent GPU calculation of
chain-input filtering and edge identity.
