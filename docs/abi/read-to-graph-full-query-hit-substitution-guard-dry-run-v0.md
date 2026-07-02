# Read-to-Graph Full Query-Hit Substitution Guard Dry-Run v0

Status: active

Created: 2026-07-01

## Purpose

This ABI documents the M6u no-mutation substitution guard for cuFlye's
read-to-graph full-query-hit worker path.

The guard runs after:

1. CUDA full-query-hit row-key validation passes.
2. Raw-overlap rehydration passes.
3. Shadow consumption ledger passes.
4. Graph-edge binding passes.
5. Object-vector smoke passes.

It receives the same graph-facing object vector shape proven by M6t at the
handoff boundary where a future milestone may replace CPU-derived read-to-graph
data. M6u records the handoff count, lightweight deterministic object order,
and accounting totals, then refuses to feed the vector into Flye graph mutation.

## Activation

The mode is disabled by default.

Enable with:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_MODE=substitution-guard-dry-run-v0
```

The only M6u proof fault is:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_PROOF_FAULT=drop-first-handoff-row
```

The proof fault removes one handoff row after M6t object-vector smoke passes.
This proves that a corrupted handoff count fails closed before graph mutation.

## Output

The audit writes:

```text
full-query-hit-worker-substitution-guard.json
```

The JSON schema name is:

```text
cuflye-read-to-graph-full-query-hit-substitution-guard-dry-run-v0
```

Required summary fields:

- `status`: `passed`, `failed`, or `not-requested`.
- `mode`: activation mode string.
- `proof_fault`: empty or `drop-first-handoff-row`.
- `proof_fault_applied`: boolean.
- `state`: consumption state, always non-consuming in M6u.
- `decision`: dry-run decision string.
- `worker_tsv`: worker raw-overlap TSV input path.
- `object_vector_smoke_status`: upstream M6t status.
- `eligible`: whether the guard passed its gates.
- `consumed`: always false in M6u.
- `not_consumed`: true when the guard passes without graph mutation.
- `failed_closed`: true when a required gate fails.
- `graph_mutation_consumed_worker_output`: always false in M6u.
- `object_vector_rows`: M6t object-vector row count.
- `object_vector_accounting_rows`: M6t object accounting row count.
- `object_vector_query_accounted_rows`: M6t query-accounted rows.
- `object_vector_edge_accounted_rows`: M6t edge-accounted rows.
- `object_vector_query_edge_accounted_rows`: M6t query-edge-accounted rows.
- `handoff_rows`: guarded handoff row count.
- `handoff_accounting_rows`: rows included in handoff accounting.
- `handoff_query_accounted_rows`: handoff query-accounted rows.
- `handoff_edge_accounted_rows`: handoff edge-accounted rows.
- `handoff_query_edge_accounted_rows`: handoff query-edge-accounted rows.
- `handoff_object_summary_rows`: number of lightweight ordered summaries.
- `missing_graph_edge_rows`: rows that could not bind to a live graph edge.
- `checks`: required gate results.
- `objects`: deterministic ordered lightweight handoff summaries.

Each `objects` entry records:

- `order_index`
- `query_id`
- `source_order`
- `edge_id`
- `read_id`
- `edge_seq_id`

## Invariants

- Substitution guard runs only after M6p, M6q, M6s, and M6t pass.
- Every guarded object must have a live `GraphEdge`.
- Handoff rows must match M6t `object_rows`.
- Handoff accounting rows must match M6t object accounting rows.
- Handoff query, edge, and query-edge accounting totals must match M6t totals.
- The guard must record deterministic object order.
- The audit never mutates graph state and never feeds the guarded handoff into
  Flye's graph update logic.

## Non-Claims

M6u does not prove whole-Flye speedup, graph mutation, real object substitution,
default GPU mode, or GPU-computed chain-input filtering/edge identity.

## M8f Selected Handoff Proof

M8f reuses this guard as the selected object-vector handoff contract for the
M8 selected source pack. The positive DGX proof records:

```text
proof_root=/tmp/cuflye-m8f-proof-20260702T000000Z
selected_query_count=16
handoff_rows=18
handoff_accounting_rows=18
handoff_object_summary_rows=18
warm_raw_overlap_substitution_guard_avg_ms=0.054832
warm_graph_facing_validation_total_avg_ms=0.368454
warm_no_mutation_seam_total_avg_ms=66.04756666666667
warm_no_mutation_seam_speedup_vs_m8a=1.2005606868181367
summary_checks_passed=30/30
```

The negative M8f proof applies
`CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SUBSTITUTION_GUARD_PROOF_FAULT=drop-first-handoff-row`
after object-vector smoke passes. Rehydration, shadow ledger, graph-edge
binding, and object-vector smoke still pass, but the guard reports
`substitution-guard-failed-before-graph-mutation` and
`graph_mutation_consumed_worker_output=false`.
