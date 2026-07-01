# ABI: Read-to-Graph Full Query-Hit Verified Substitution Smoke v0

Status: proposed

Created: 2026-07-01

## Purpose

`cuflye-read-to-graph-full-query-hit-verified-substitution-smoke-v0` is an
opt-in no-mutation audit for the CUDA full-query-hit worker path.

It runs after the M6u substitution guard has accepted a CUDA-derived
graph-facing object vector. The smoke audit compares the would-substitute rows
against the selected CPU oracle handoff shape, writes a rollback-safe
substitution ledger, and still prevents the ledger from being consumed by Flye
graph mutation.

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
```

Negative proof injection:

```bash
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_VERIFIED_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-ledger-row
```

## Output

Flye writes:

```text
full-query-hit-worker-verified-substitution-smoke.json
```

The worker dry-run audit also mirrors the status and row counts:

```json
{
  "raw_overlap_verified_substitution_json": ".../full-query-hit-worker-verified-substitution-smoke.json",
  "raw_overlap_verified_substitution_status": "passed",
  "raw_overlap_verified_substitution_cpu_handoff_rows": 8,
  "raw_overlap_verified_substitution_would_substitute_rows": 8,
  "raw_overlap_verified_substitution_ledger_rows": 8
}
```

## Standalone JSON Schema

Top-level fields:

| Field | Meaning |
| --- | --- |
| `schema` | Always `cuflye-read-to-graph-full-query-hit-verified-substitution-smoke-v0`. |
| `status` | `passed`, `failed`, or `not-requested`. |
| `mode` | The requested mode string. |
| `proof_fault` | Empty or `drop-first-substitution-ledger-row`. |
| `proof_fault_applied` | Whether the negative proof fault changed the ledger. |
| `state` | `not-consumed` or `failed-closed`. |
| `decision` | Human-readable final gate decision. |
| `substitution_guard_status` | M6u guard status. |
| `eligible` | Whether the would-substitute ledger passed all checks. |
| `consumed` | Always false in v0. |
| `not_consumed` | True only when the ledger was not consumed by graph mutation. |
| `failed_closed` | True when any required check failed. |
| `row_key_matched` | Canonical row-key match against selected CPU handoff rows. |
| `ordered_row_key_matched` | Order-sensitive row-key match against selected CPU handoff rows. |
| `guard_handoff_rows` | M6u guarded handoff object count. |
| `selected_cpu_handoff_rows` | CPU oracle chain-input/resolved-edge selected rows. |
| `would_substitute_rows` | CUDA-derived rows that would be substituted. |
| `substitution_ledger_rows` | Rows recorded in the rollback-safe ledger. |
| `checks` | Required gate checks and details. |
| `ledger` | Deterministic would-substitute row summaries. |
| `row_key_diff` | Canonical CPU-vs-ledger row-key diff. |

Each `ledger` row contains:

| Field | Meaning |
| --- | --- |
| `order_index` | Deterministic ledger order. |
| `query_id` | Flye query read id. |
| `source_order` | Original full-query-hit source-pack row order. |
| `edge_id` | Live graph edge id used for the would-substitute object. |
| `read_id` | `OverlapRange.curId`. |
| `edge_seq_id` | `OverlapRange.extId`. |

## Invariants

- The mode cannot run unless M6p, M6q, M6s, M6t, and M6u are enabled.
- The worker raw-overlap row-key gate must already match the CPU oracle.
- M6u substitution guard must pass first.
- Positive proof requires nonzero selected CPU handoff rows.
- Positive proof requires `would_substitute_rows == guard_handoff_rows`.
- Positive proof requires `substitution_ledger_rows == guard_handoff_accounting_rows`.
- Positive proof requires canonical and ordered row-key equality against the
  selected CPU handoff rows.
- The ledger is not consumed by graph mutation in v0.
- Negative proof with `drop-first-substitution-ledger-row` must fail closed
  before graph mutation.

## Non-Claims

This ABI does not prove default GPU mode, real Flye graph mutation, repeat
graph simplification changes, whole-Flye speedup, or independent GPU
calculation of chain-input filtering and edge identity.
