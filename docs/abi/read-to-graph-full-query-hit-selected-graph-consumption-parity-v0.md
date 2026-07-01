# ABI: Read-to-Graph Full Query-Hit Selected Graph-Consumption Parity v0

Status: accepted in M7a

Created: 2026-07-01

## Purpose

`cuflye-read-to-graph-full-query-hit-selected-graph-consumption-parity-v0` is
an opt-in no-mutation gate after M6z.

It verifies that the M6y/M6z final merged selected handoff can be represented
as graph-facing rows with live Flye graph edges: CUDA-supplied selected rows
plus CPU-owned residual rows. It still stops before graph mutation.

## Activation

Enable all M6z gates, then add:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_MODE=selected-graph-consumption-parity-v0
```

Negative proof injection:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_PROOF_FAULT=drop-first-graph-facing-row
```

## Output

Flye writes:

```text
full-query-hit-worker-selected-graph-consumption-parity.json
```

The worker dry-run audit mirrors status and row counts:

```json
{
  "raw_overlap_selected_graph_consumption_parity_status": "passed",
  "raw_overlap_selected_graph_consumption_parity_graph_facing_rows": 36,
  "raw_overlap_selected_graph_consumption_parity_cuda_supplied_rows": 8,
  "raw_overlap_selected_graph_consumption_parity_cpu_owned_rows": 28,
  "raw_overlap_selected_graph_consumption_parity_missing_graph_edge_rows": 0
}
```

## Fields

| Field | Meaning |
| --- | --- |
| `schema` | Always `cuflye-read-to-graph-full-query-hit-selected-graph-consumption-parity-v0`. |
| `status` | `passed`, `failed`, or `not-requested`. |
| `mode` | The requested mode string. |
| `proof_fault` | Empty or `drop-first-graph-facing-row`. |
| `proof_fault_applied` | Whether the negative proof fault changed the graph-facing ledger. |
| `selected_cpu_bypass_smoke_status` | M6y/M6z selected CPU-bypass smoke status. |
| `consumed` | Always false in v0. |
| `not_consumed` | True only when the graph-facing parity output was not consumed by graph mutation. |
| `graph_facing_rows` | Rows in the graph-facing handoff ledger. |
| `final_merged_ledger_rows` | Rows in the M6y/M6z final merged ledger. |
| `graph_facing_cuda_supplied_rows` | CUDA-supplied selected rows in the graph-facing handoff. |
| `graph_facing_cpu_owned_rows` | CPU-owned residual rows in the graph-facing handoff. |
| `missing_graph_edge_rows` | Rows that do not bind to a live Flye `GraphEdge`. |
| `dropped_graph_facing_rows` | Rows intentionally dropped by the negative proof fault. |
| `timing_ms.graph_facing_build` | Time to build and validate the graph-facing parity ledger. |
| `timing_ms.graph_consumption_parity_total` | Total M7a parity gate time. |
| `graph_facing_ledger` | Deterministic graph-facing ledger rows. |

## Invariants

- M7a cannot run unless M6y/M6z selected CPU-bypass smoke passes.
- M6z timing fields must be present before M7a is trusted.
- The graph-facing row count must equal the M6y final merged ledger row count.
- CUDA-supplied and CPU-owned row counts must match the M6y/M6z smoke counts.
- Every graph-facing row must bind to a live Flye graph edge using Flye signed
  id conversion.
- The gate is not consumed by graph mutation in v0.
- Negative proof with `drop-first-graph-facing-row` must fail closed before
  graph mutation.

## Non-Claims

This ABI does not prove default GPU mode, whole-Flye speedup, or real graph
mutation. It only proves the selected merged handoff can reach a graph-facing
live-edge parity boundary.
