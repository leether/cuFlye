# Task Card: cuFlye M6v Full Query-Hit Verified Substitution Smoke

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6u's guarded substitution handoff into the first verified
substitution smoke for CUDA full-query-hit rows.

M6u proves that Flye can receive the CUDA-derived graph-facing object vector at
a guarded handoff and fail closed on a corrupted count before graph mutation.
M6v should add an opt-in no-mutation smoke path that validates whether the
guarded vector is eligible to replace the matched CPU-derived handoff for the
selected rows, records a rollback-safe substitution ledger, and still blocks
real graph mutation.

## In Scope

- Add an opt-in verified-substitution-smoke mode after M6u passes.
- Compare CUDA handoff objects with the matched CPU-derived selected handoff
  shape before any replacement is allowed.
- Record would-substitute row counts, query/edge accounting, and a
  rollback-safe substitution ledger.
- Prove the substitution decision is not consumed by graph mutation.
- Add a negative proof fault that corrupts the substitution ledger and fails
  closed before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No real graph mutation or graph simplification change.
- No unguarded replacement of Flye's CPU read-to-graph path.
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
  smoke, substitution-guard, or verified-substitution gate fails.

## Deliverables

- Flye patch implementing the opt-in verified-substitution smoke audit.
- ABI/design notes for the verified-substitution JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [x] M6p, M6q, M6s, M6t, and M6u gates must pass before verified
      substitution smoke runs.
- [x] Positive DGX proof records nonzero would-substitute rows.
- [x] Positive DGX proof substitution ledger count equals guarded handoff
      object count.
- [x] Positive DGX proof proves the substitution decision is not consumed by
      graph mutation.
- [x] Negative proof fails closed before graph mutation when the substitution
      ledger is intentionally corrupted.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in patch
`patches/flye/2.9.6/0050-cuflye-read-to-graph-full-query-hit-verified-substitution-smoke.patch`.

ABI:

- `docs/abi/read-to-graph-full-query-hit-verified-substitution-smoke-v0.md`

DGX proof:

```text
proof_root=/tmp/cuflye-m6v-proof-20260701T113000Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_status=passed
positive_rehydration_status=passed
positive_shadow_ledger_status=passed
positive_graph_edge_binding_status=passed
positive_object_vector_smoke_status=passed
positive_substitution_guard_status=passed
positive_verified_substitution_status=passed
positive_guard_handoff_rows=8
positive_selected_cpu_handoff_rows=8
positive_would_substitute_rows=8
positive_substitution_ledger_rows=8
positive_substitution_row_key_diff_status=match
positive_substitution_ordered_row_key_matched=true
positive_graph_mutation_consumed_worker_output=false
negative_status=verified-substitution-smoke-failed-before-graph-mutation
negative_verified_substitution_status=failed
negative_proof_fault=drop-first-substitution-ledger-row
negative_proof_fault_applied=true
negative_guard_handoff_rows=8
negative_would_substitute_rows=7
negative_substitution_ledger_rows=7
negative_substitution_row_key_diff_status=mismatch
negative_substitution_guard_status=passed
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Golden manifest:

- `tests/golden/cuflye-m6v-full-query-hit-verified-substitution-smoke-dgx-aarch64.json`

Plain-language benefit:

```text
M6v still does not make full Flye faster. It proves the selected CUDA-derived
object vector is not just count-compatible with Flye: its would-substitute
ledger matches the selected CPU handoff row keys and order, and a corrupted
ledger is rejected before graph mutation.
```
