# ABI: Read-to-Graph Full Query-Hit Selected Graph-Consumption Mutation Canary v0

Status: accepted in M7b

Created: 2026-07-01

## Purpose

`cuflye-read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary-v0`
is an opt-in guarded mutation canary after M7a.

M7a proves the selected CUDA-supplied handoff can be represented as live
graph-facing rows but does not consume those rows. M7b rebuilds Flye
`goodChains` for the selected query set from the full-query-hit worker output,
compares them against the existing CPU `_readAlignments` slice, and replaces
only that selected forward plus complement slice when the canonical records are
identical.

## Activation

Enable the M6y/M6z gates and M7a parity, then add:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_MODE=selected-graph-consumption-mutation-canary-v0
```

Negative proof injection:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_MUTATION_CANARY_PROOF_FAULT=drop-first-canary-chain
```

The mode is rejected unless
`CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SELECTED_GRAPH_CONSUMPTION_PARITY_MODE=selected-graph-consumption-parity-v0`
is also enabled.

## Output

Flye writes:

```text
full-query-hit-worker-selected-graph-consumption-mutation-canary.json
```

The worker dry-run audit mirrors the canary decision:

```json
{
  "raw_overlap_selected_graph_consumption_mutation_canary_status": "passed",
  "raw_overlap_selected_graph_consumption_mutation_canary_state": "consumed",
  "raw_overlap_selected_graph_consumption_mutation_canary_decision": "selected-graph-consumption-mutation-canary-substituted",
  "raw_overlap_selected_graph_consumption_mutation_canary_rebuilt_good_chains": 8,
  "raw_overlap_selected_graph_consumption_mutation_canary_substituted_chains": 16,
  "graph_mutation_consumed_worker_output": true
}
```

## Fields

| Field | Meaning |
| --- | --- |
| `schema` | Always `cuflye-read-to-graph-full-query-hit-selected-graph-consumption-mutation-canary-v0`. |
| `status` | `passed`, `failed`, or `not-requested`. |
| `mode` | The requested mode string. |
| `proof_fault` | Empty or `drop-first-canary-chain`. |
| `proof_fault_applied` | Whether the negative proof fault changed the rebuilt selected chain set. |
| `state` | `consumed`, `failed-closed`, or `not-consumed`. |
| `decision` | Human-readable canary decision string. |
| `selected_graph_consumption_parity_status` | Required M7a parity result. |
| `eligible` | Whether all preconditions made the canary eligible. |
| `attempted` | Whether the canary attempted the selected rebuild/compare path. |
| `accepted` | Whether the canary accepted the rebuilt selected chains. |
| `consumed` | True only when the selected rebuilt chains replace the selected `_readAlignments` slice. |
| `failed_closed` | True when the canary rejects the handoff before graph mutation commit. |
| `graph_mutation_consumed_worker_output` | True only for the guarded positive canary path. |
| `selected_canary_records_matched` | Whether rebuilt selected records match the CPU slice records. |
| `final_alignment_records_matched` | Whether whole `_readAlignments` canonical records remain identical after substitution. |
| `selected_query_count` | Number of selected query ids in the canary. |
| `worker_records` | Full-query-hit worker raw-overlap rows available to the canary. |
| `chain_input_rows` | Rows selected for chain input. |
| `missing_graph_edge_rows` | Chain-input rows missing live graph edge binding. |
| `rebuilt_pre_divergence_chains` | Selected chains rebuilt before divergence filtering. |
| `rebuilt_good_chains` | Selected chains accepted by Flye `getChainBaseDivergence`. |
| `rebuilt_good_records` | Canonical selected records produced by rebuilt `goodChains`. |
| `cpu_slice_chains` | Existing selected CPU/GPU slice chains in `_readAlignments`. |
| `cpu_slice_records` | Canonical records from the selected `_readAlignments` slice. |
| `total_read_alignments_before` | Whole `_readAlignments` chain count before substitution. |
| `total_read_alignments_after` | Whole `_readAlignments` chain count after substitution. |
| `substituted_forward_chains` | Forward selected chains replaced by rebuilt output. |
| `substituted_complement_chains` | Complement selected chains replaced by rebuilt output. |
| `timing_ms.rebuild` | Time to rebuild selected chains from worker rows. |
| `timing_ms.compare` | Time to canonicalize and compare selected records. |
| `timing_ms.substitution` | Time to replace selected forward/complement chains and verify whole-record parity. |
| `timing_ms.total` | Total mutation canary gate time. |
| `checks` | Required machine-readable pass/fail checks. |

## Invariants

- M7b cannot run unless M7a selected graph-consumption parity has passed.
- M7b cannot run unless M6y selected CPU-bypass smoke has passed.
- The worker raw-overlap TSV must be readable and must contain chain-input
  rows for the selected query set.
- Every selected canary row must bind to a live `GraphEdge*`; raw pointers are
  non-owning and remain `RepeatGraph`-owned.
- Rebuilt selected `goodChains` must canonicalize to the same records as the
  existing selected `_readAlignments` CPU slice.
- Both forward selected chains and their complement chains must be substituted.
- Whole `_readAlignments` canonical records must match before the canary can
  mark the handoff consumed.
- Negative proof with `drop-first-canary-chain` must fail closed before graph
  mutation commit.

## Non-Claims

This ABI does not prove default GPU mode, whole-Flye speedup, or broad
read-to-graph CPU elimination. It proves only that a tiny selected
full-query-hit worker handoff can be rebuilt into Flye `goodChains`, consumed
by the graph-facing alignment slice, and still preserve canonical Flye
artifacts.
