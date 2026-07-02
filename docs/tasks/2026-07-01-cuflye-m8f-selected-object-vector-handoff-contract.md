# Task Card: cuFlye M8f Selected Object-Vector Handoff Contract

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M8e object-vector smoke result into a tighter no-mutation graph-facing
handoff contract for the same M8 selected source pack.

M8e proved that `18` selected rows can bind to live `GraphEdge` objects and be
accounted as object-vector smoke rows while preserving the selected CUDA
advantage. M8f should define the exact handoff record shape that a later
mutation canary would consume, without enabling unguarded graph mutation.

## In Scope

- Reuse the exact M8 selected source pack and query ids.
- Keep `session-file-v0`, row-key diff, raw-overlap rehydration, shadow ledger,
  graph-edge binding, and object-vector smoke gates enabled.
- Define a compact graph-facing handoff summary for the selected object-vector
  rows, including query id, edge id, read id, source order, and deterministic
  ordering.
- Add timing attribution for the handoff contract build and validation.
- Add a negative proof fault that corrupts the handoff accounting and fails
  closed before graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No object-vector substitution into Flye graph update logic.
- No whole-Flye speed claim.
- No expansion beyond the M8 selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing graph-facing object helpers and non-owning `GraphEdge*`
  conventions.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep every worker-derived handoff record behind row-key, rehydration,
  shadow-ledger, graph-edge binding, object-vector, and handoff diff gates.
- Unsupported or mismatched output must fail closed before graph mutation.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- ABI notes for the selected object-vector handoff contract.
- Timing attribution showing whether the handoff contract preserves the M8e
  warm no-mutation advantage.
- Task Card, ABI, and ROADMAP updates with allowed and forbidden claims.

## Acceptance Gates

- [x] Reuses the exact M8 selected source pack and records the same canonical
      source-pack SHA.
- [x] Worker row-key output, raw-overlap rehydration, shadow ledger,
      graph-edge binding, and object-vector smoke pass.
- [x] Handoff rows equal M8e selected object-vector rows and remain
      deterministically ordered.
- [x] M8a chain-input oracle pack replay remains `match`.
- [x] Canonical Flye artifacts remain unchanged.
- [x] Timing separates handoff build/validation from worker and prior
      graph-facing gate costs.
- [x] Negative handoff proof fails closed before unguarded graph mutation.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented by:

- `patches/flye/2.9.6/0060-cuflye-read-to-graph-full-query-hit-handoff-contract-timing.patch`
- `scripts/run_m8f_selected_object_vector_handoff_contract.sh`
- `tests/golden/cuflye-m8f-selected-object-vector-handoff-contract-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m8f-proof-20260702T000000Z
fixture=toy-hifi
selected_query_count=16
m8a_selected_quick_overlap_ms=79.294112
m8b_source_pack_sha256=5fb1df86185f3cdce0bc0c15087b7bead53db6d46b523740650d4092a89c25aa
source_pack_raw_overlap_records=27
source_pack_chain_input_records=18
positive_object_vector_rows=18
positive_substitution_guard_handoff_rows=18
positive_substitution_guard_accounting_rows=18
positive_substitution_guard_object_summary_rows=18
warm_handoff_contract_avg_ms=0.054832
warm_graph_edge_binding_avg_ms=0.05582433333333333
warm_object_vector_smoke_avg_ms=0.06478400000000001
warm_graph_facing_validation_total_avg_ms=0.368454
warm_no_mutation_seam_total_avg_ms=66.04756666666667
warm_no_mutation_seam_speedup_vs_m8a=1.2005606868181367
negative_handoff_status=substitution-guard-failed-before-graph-mutation
negative_handoff_rehydration_status=passed
negative_handoff_shadow_status=passed
negative_handoff_binding_status=passed
negative_handoff_object_status=passed
negative_handoff_guard_status=failed
negative_handoff_graph_mutation_consumed_worker_output=false
summary_checks_passed=30/30
```

Plain-language benefit:

M8f shows that the selected CUDA path can turn the `18` live
`GraphEdge`-bound object-vector rows into a deterministic no-mutation handoff
contract. The handoff contract costs about `0.055 ms` on warm requests, and the
warm no-mutation seam remains faster than the matched CPU quick-overlap
baseline: `66.047567 ms` vs `79.294112 ms`, or `1.201x`.

M8f still does not prove default GPU mode, unguarded graph mutation,
object-vector substitution into Flye graph update logic, full non-key
raw-overlap field parity, or whole-Flye speedup.
