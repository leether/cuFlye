# Read-to-Graph Full Query-Hit Shadow Consumption Ledger v0

Status: accepted in M6q

Introduced: M6q

Scope: Flye-side no-mutation ledger for M6p-rehydrated CUDA full-query-hit
raw-overlap rows.

## Purpose

`cuflye-read-to-graph-full-query-hit-shadow-consumption-ledger-v0` records what
the validated CUDA full-query-hit output would be eligible for next, without
feeding any worker row into Flye graph mutation.

M6p proves that CUDA worker rows can be parsed back into Flye-side
`OverlapRange`-shaped records. M6q adds deterministic accounting over those
typed rows:

- total worker and rehydrated rows;
- rows that pass the chain-input filter;
- rows whose `edge_id` is still unresolved as `0`;
- rows with resolved `edge_id`;
- future raw-overlap and chain-input shadow eligibility;
- graph-edge consumption candidates, fixed at `0` in M6q.

## Selector

The ledger is disabled by default. It is enabled only when:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_MODE=raw-overlap-chain-input-shadow-v0
```

It requires:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE=full-query-hit-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_REHYDRATION_MODE=raw-overlap-vector-dry-run-v0
```

Unsupported values fail closed before graph mutation. A proof fault without the
ledger mode also fails closed during configuration validation.

## Proof Fault

M6q supports one proof-only fault:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_SHADOW_LEDGER_PROOF_FAULT=drop-first-ledger-row
```

The fault is applied after M6p rehydration has passed. It drops one row from the
ledger accounting, causing `ledger_count_matches_rehydration` to fail. This
proves the ledger gate fails closed independently of the M6p typed row-key gate.

## Generated Files

When enabled, Flye writes:

```text
full-query-hit-worker-shadow-consumption-ledger.json
```

with schema:

```json
{
  "schema": "cuflye-read-to-graph-full-query-hit-shadow-consumption-ledger-v0",
  "status": "passed",
  "mode": "raw-overlap-chain-input-shadow-v0",
  "state": "not-consumed",
  "decision": "shadow-ledger-written-not-consumed",
  "rehydration_status": "passed",
  "ledger_rows": 36,
  "chain_input_filter_rows": 0,
  "unresolved_edge_id_zero_rows": 36,
  "resolved_edge_id_rows": 0,
  "future_raw_overlap_shadow_rows": 36,
  "future_chain_input_shadow_rows": 0,
  "graph_edge_consumption_candidate_rows": 0,
  "graph_mutation_consumed_worker_output": false
}
```

`full-query-hit-worker-dry-run.json` also records the ledger mode, status,
decision, row counts, and graph-consumption candidate count.

## Required Checks

| Check | Meaning |
| --- | --- |
| `explicit_shadow_ledger_mode` | The mode is explicitly `raw-overlap-chain-input-shadow-v0`. |
| `rehydration_passed` | M6p rehydration passed first. |
| `worker_output_readable` | The validated worker TSV is readable. |
| `audit_metadata_available` | Ledger audit JSON path is available. |
| `graph_not_mutated` | Worker output has not reached graph mutation. |
| `ledger_count_matches_rehydration` | Ledger row count equals M6p rehydrated record count. |
| `edge_id_rows_accounted` | Every row is counted as unresolved `edge_id=0` or resolved `edge_id!=0`. |
| `graph_edge_consumption_candidates_blocked` | M6q exposes zero graph-edge consumption candidates. |
| `graph_not_mutated_after_ledger` | Ledger evaluation still has not mutated graph state. |

## Failure Semantics

If M6p rehydration is absent, failed, or if the ledger proof fault corrupts row
accounting, Flye writes the ledger JSON when possible, marks
`raw_overlap_shadow_ledger_status=failed`, keeps
`graph_mutation_consumed_worker_output=false`, and exits non-zero before graph
mutation. There is no silent CPU fallback when the seam is explicitly enabled.

## M6q Benefit Assessment

M6q still does not make full Flye faster. Its value is decision quality: it
shows that the current CUDA full-query-hit rows are good enough for future
raw-overlap shadowing, but the selected proof exposes zero chain-input rows and
zero graph-edge consumption candidates. The next blocker is therefore a narrower
chain-input or graph-edge identity gate, not row-key parity or typed parsing.
