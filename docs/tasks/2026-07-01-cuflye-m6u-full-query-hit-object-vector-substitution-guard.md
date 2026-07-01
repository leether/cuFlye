# Task Card: cuFlye M6u Full Query-Hit Object Vector Substitution Guard

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6t object-vector smoke into a guarded no-mutation substitution
handoff for CUDA full-query-hit rows.

M6t proves that chain-input-positive worker rows can become graph-facing
objects tied to live Flye `GraphEdge*` pointers and fully accounted by query and
edge. M6u should define the first substitution guard that receives this object
vector at the boundary where Flye would otherwise continue with CPU-derived
read-to-graph data, records the exact handoff decision, and still prevents real
graph mutation.

## In Scope

- Add an opt-in substitution-guard mode after M6t object-vector smoke passes.
- Preserve deterministic object order and record the handoff count.
- Prove the guard sees exactly the same object count and accounting totals as
  M6t.
- Prove the guard does not consume the vector into graph mutation.
- Add a negative proof fault that corrupts the handoff count and fails closed
  before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No real graph mutation or graph simplification change.
- No replacement of Flye's CPU read-to-graph path.
- No whole-Flye speedup claim.
- No GPU-computed chain-input filtering or edge identity claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and scoped to the live
  `RepeatGraph`.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs.
- Fail closed if any row-key, rehydration, ledger, binding, object-vector
  smoke, or substitution-guard gate fails.

## Deliverables

- Flye patch implementing the opt-in substitution-guard audit.
- ABI/design notes for the substitution-guard JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6p, M6q, M6s, and M6t gates must pass before substitution guard runs.
- [x] Positive DGX proof records nonzero guarded handoff objects.
- [x] Positive DGX proof handoff count equals M6t object-vector count.
- [x] Positive DGX proof proves the handoff is not consumed by graph mutation.
- [x] Negative proof fails closed before graph mutation when the handoff count
      is intentionally corrupted.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in patch
`patches/flye/2.9.6/0049-cuflye-read-to-graph-full-query-hit-substitution-guard.patch`.

ABI:

- `docs/abi/read-to-graph-full-query-hit-substitution-guard-dry-run-v0.md`

DGX proof:

```text
proof_root=/tmp/cuflye-m6u-proof-20260701T111200Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_object_vector_smoke_status=passed
positive_substitution_guard_status=passed
positive_object_rows=8
positive_handoff_rows=8
positive_handoff_accounting_rows=8
positive_handoff_query_accounted_rows=8
positive_handoff_edge_accounted_rows=8
positive_handoff_query_edge_accounted_rows=8
positive_handoff_object_summary_rows=8
positive_graph_mutation_consumed_worker_output=false
negative_status=substitution-guard-failed-before-graph-mutation
negative_substitution_guard_status=failed
negative_proof_fault=drop-first-handoff-row
negative_proof_fault_applied=true
negative_object_rows=8
negative_handoff_rows=7
negative_object_vector_smoke_status=passed
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Golden manifest:

- `tests/golden/cuflye-m6u-full-query-hit-substitution-guard-dgx-aarch64.json`

Plain-language benefit:

```text
M6u still does not make full Flye faster. It proves the CUDA-derived
graph-facing object vector can reach a guarded substitution handoff, and that
Flye rejects a corrupted handoff count before any graph mutation can consume
the vector.
```
