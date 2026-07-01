# Read-to-Graph Full Query-Hit Graph Edge Binding Dry-Run v0

Status: proposed

Created: 2026-07-01

## Purpose

This ABI documents the M6s no-mutation graph-edge binding audit for cuFlye's
read-to-graph full-query-hit worker path.

The audit runs after:

1. CUDA full-query-hit row-key validation passes.
2. Raw-overlap rehydration passes.
3. Shadow consumption ledger passes.

It checks whether chain-input-positive CUDA worker rows with resolved `edge_id`
values can be mapped back to live Flye `GraphEdge*` objects through the current
`RepeatGraph::getEdge()` index.

## Activation

The mode is disabled by default.

Enable with:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_MODE=graph-edge-binding-dry-run-v0
```

The only M6s proof fault is:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_GRAPH_EDGE_BINDING_PROOF_FAULT=drop-first-binding-row
```

## Output

The audit writes:

```text
full-query-hit-worker-graph-edge-binding.json
```

The JSON schema name is:

```text
cuflye-read-to-graph-full-query-hit-graph-edge-binding-dry-run-v0
```

Required summary fields:

- `status`: `passed`, `failed`, or `not-requested`.
- `mode`: activation mode string.
- `proof_fault`: empty or `drop-first-binding-row`.
- `proof_fault_applied`: boolean.
- `state`: consumption state, always non-consuming in M6s.
- `decision`: dry-run decision string.
- `worker_tsv`: worker raw-overlap TSV input path.
- `ledger_status`: upstream M6q ledger status.
- `eligible`: whether the binding audit passed its gates.
- `consumed`: always false in M6s.
- `not_consumed`: true when audit passes without graph mutation.
- `failed_closed`: true when a required gate fails.
- `graph_mutation_consumed_worker_output`: always false in M6s.
- `ledger_rows`: M6q ledger row count.
- `chain_input_filter_rows`: M6q chain-input-positive row count.
- `binding_rows`: rows inspected by this binding audit.
- `resolved_edge_id_rows`: binding rows with nonzero `edge_id`.
- `live_graph_edge_rows`: binding rows mapped to live `GraphEdge*`.
- `missing_graph_edge_rows`: binding rows without a live graph edge.
- `checks`: required gate results.
- `queries`: per-query binding counters.

## Invariants

- Binding runs only after M6p rehydration and M6q shadow ledger pass.
- Only rows with `passes_chain_input_filter=1` are binding candidates.
- Every binding candidate must have nonzero `edge_id`.
- Every binding candidate `edge_id` must resolve through
  `RepeatGraph::getEdge()`.
- The audit never mutates graph state and never feeds worker output into Flye's
  graph update logic.

## Non-Claims

M6s does not prove whole-Flye speedup, GPU-computed chain-input filtering,
GPU-computed edge identity, graph mutation, or a default GPU mode.

## M8e Selected Proof

M8e reused this graph-edge binding gate for the M8 selected source pack. The
selected CUDA worker output produced `27` rehydrated raw-overlap rows and `18`
chain-input-positive rows. All `18` binding rows had nonzero `edge_id` values
and resolved to live Flye `GraphEdge` objects.

Timing in the M8e DGX proof:

```text
warm_graph_edge_binding_avg_ms=0.05335466666666666
warm_object_vector_smoke_avg_ms=0.061664
warm_graph_facing_validation_total_avg_ms=0.313323
warm_no_mutation_seam_total_avg_ms=66.49926666666666
```

The binding gate remains non-consuming: it proves live graph-edge identity for
the selected rows, then passes the checked rows to the object-vector smoke gate
without feeding worker output into graph mutation.
