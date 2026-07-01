# Task Card: cuFlye M6t Full Query-Hit Object Vector Consumption Smoke

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6s graph-edge binding into a no-mutation object-vector consumption
smoke test for CUDA full-query-hit rows.

M6s proves that every chain-input-positive selected worker row can bind back to
a live Flye `GraphEdge*`. M6t should build the first graph-facing in-memory
object vector from those rows, account every object, and still prevent that
vector from being returned into Flye's mutating read-to-graph path.

## In Scope

- Add an opt-in object-vector smoke mode after M6s graph-edge binding passes.
- Construct bounded graph-facing objects from chain-input-positive worker rows
  using the live `GraphEdge*` bindings.
- Record deterministic object counts by query and edge.
- Prove the constructed vector is not consumed by graph mutation.
- Add a negative proof fault that corrupts object accounting and fails closed
  before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No replacement of Flye's CPU read-to-graph path.
- No real graph mutation or graph simplification change.
- No whole-Flye speedup claim.
- No GPU-computed chain-input filtering or edge identity claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Use non-owning `GraphEdge*` only when the owner and lifetime are the live
  `RepeatGraph`.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs.
- Fail closed if any row-key, rehydration, ledger, binding, or object
  accounting gate fails.

## Deliverables

- Flye patch implementing the opt-in object-vector smoke audit.
- ABI/design notes for the object-vector smoke JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6p, M6q, and M6s gates must pass before object-vector smoke runs.
- [x] Positive DGX proof records nonzero constructed graph-facing objects.
- [x] Positive DGX proof accounts every object by query and edge.
- [x] Positive DGX proof proves the object vector is not consumed by graph
      mutation.
- [x] Negative proof fails closed before graph mutation when object accounting
      is intentionally corrupted.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in patch
`patches/flye/2.9.6/0048-cuflye-read-to-graph-full-query-hit-object-vector-smoke.patch`.

ABI:

- `docs/abi/read-to-graph-full-query-hit-object-vector-smoke-v0.md`

DGX proof:

```text
proof_root=/tmp/cuflye-m6t-proof-20260701T105600Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_object_vector_smoke_status=passed
positive_object_rows=8
positive_object_accounting_rows=8
positive_query_accounted_rows=8
positive_edge_accounted_rows=8
positive_query_edge_accounted_rows=8
positive_graph_mutation_consumed_worker_output=false
negative_status=object-vector-smoke-failed-before-graph-mutation
negative_object_vector_smoke_status=failed
negative_proof_fault=drop-first-object-accounting-row
negative_proof_fault_applied=true
negative_object_rows=8
negative_object_accounting_rows=7
negative_graph_edge_binding_status=passed
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Golden manifest:

- `tests/golden/cuflye-m6t-full-query-hit-object-vector-smoke-dgx-aarch64.json`

Plain-language benefit:

```text
M6t still does not make full Flye faster. It proves that the CUDA-derived
full-query-hit rows can become real graph-facing in-memory objects tied to live
Flye edges, and that every object can be accounted by query and edge before any
graph mutation is allowed to see the vector.
```
