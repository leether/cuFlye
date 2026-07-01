# Read-to-Graph Full Query-Hit Object-Vector Smoke v0

Status: proposed

Created: 2026-07-01

## Purpose

This ABI documents the M6t no-mutation object-vector smoke audit for cuFlye's
read-to-graph full-query-hit worker path.

The audit runs after:

1. CUDA full-query-hit row-key validation passes.
2. Raw-overlap rehydration passes.
3. Shadow consumption ledger passes.
4. Graph-edge binding passes.

It constructs a bounded in-memory vector of graph-facing objects from
chain-input-positive worker rows. Each object carries the worker raw-overlap
record plus a non-owning pointer to the live Flye `GraphEdge` resolved by M6s.
The vector is accounted by query, edge, and query-edge pair, then discarded
before any Flye graph mutation path can consume it.

## Activation

The mode is disabled by default.

Enable with:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_MODE=object-vector-smoke-v0
```

The only M6t proof fault is:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_OBJECT_VECTOR_SMOKE_PROOF_FAULT=drop-first-object-accounting-row
```

The proof fault removes one row from accounting only, leaving the constructed
object vector intact. This proves accounting corruption fails closed before
graph mutation.

## Output

The audit writes:

```text
full-query-hit-worker-object-vector-smoke.json
```

The JSON schema name is:

```text
cuflye-read-to-graph-full-query-hit-object-vector-smoke-v0
```

Required summary fields:

- `status`: `passed`, `failed`, or `not-requested`.
- `mode`: activation mode string.
- `proof_fault`: empty or `drop-first-object-accounting-row`.
- `proof_fault_applied`: boolean.
- `state`: consumption state, always non-consuming in M6t.
- `decision`: dry-run decision string.
- `worker_tsv`: worker raw-overlap TSV input path.
- `binding_status`: upstream M6s binding status.
- `eligible`: whether the smoke audit passed its gates.
- `consumed`: always false in M6t.
- `not_consumed`: true when audit passes without graph mutation.
- `failed_closed`: true when a required gate fails.
- `graph_mutation_consumed_worker_output`: always false in M6t.
- `chain_input_filter_rows`: M6s chain-input-positive row count.
- `binding_rows`: M6s bound row count.
- `object_rows`: constructed object-vector rows.
- `object_accounting_rows`: rows included in accounting.
- `query_accounted_rows`: sum of per-query object rows.
- `edge_accounted_rows`: sum of per-edge object rows.
- `query_edge_accounted_rows`: sum of per-query-edge object rows.
- `query_summary_rows`: number of query summaries.
- `edge_summary_rows`: number of edge summaries.
- `query_edge_summary_rows`: number of query-edge summaries.
- `missing_graph_edge_rows`: rows that could not be bound to a live edge.
- `checks`: required gate results.
- `queries`: deterministic per-query object counts.
- `edges`: deterministic per-edge object counts.
- `query_edges`: deterministic per-query-edge object counts.

## Invariants

- Object-vector smoke runs only after M6p, M6q, and M6s pass.
- Only rows with `passes_chain_input_filter=1` are object candidates.
- Every object candidate must have nonzero `edge_id`.
- Every object candidate `edge_id` must resolve through
  `RepeatGraph::getEdge()`.
- The constructed object count must equal the M6s binding row count.
- Query, edge, and query-edge accounting sums must each equal the constructed
  object count.
- The audit never mutates graph state and never feeds the constructed vector
  into Flye's graph update logic.

## Non-Claims

M6t does not prove whole-Flye speedup, graph mutation, object substitution,
default GPU mode, or GPU-computed chain-input filtering/edge identity.
