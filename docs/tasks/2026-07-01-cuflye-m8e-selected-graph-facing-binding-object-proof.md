# Task Card: cuFlye M8e Selected Graph-Facing Binding Object Proof

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M8d shadow-ledger accounting to the next guarded graph-facing proof
for the same M8b/M8c selected source pack.

M8d showed that row-key diff, raw-overlap rehydration, and shadow ledger
validation add only about `0.210 ms` on warm requests and preserve a bounded
selected CUDA advantage. M8e should test whether the next binding or
object-vector gate can also remain below the matched M8a CPU quick-overlap
baseline while still preventing unguarded graph mutation.

## In Scope

- Reuse the exact M8b/M8c/M8d selected source pack and query ids.
- Reuse `session-file-v0`, raw-overlap rehydration, and shadow ledger gates.
- Enable the next already-defined graph-facing binding or object-vector proof
  path for the selected rows.
- Attribute worker session, row-key diff, rehydration, shadow ledger, next
  graph-facing gate, and total no-mutation seam time.
- Preserve canonical Flye artifacts and fail closed on proof faults before
  unguarded graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No whole-Flye speed claim.
- No expansion beyond the M8 selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing graph-facing binding/object helpers and RAII wrappers.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep every worker-derived object behind row-key, rehydration, shadow-ledger,
  and graph-facing diff gates.
- Unsupported or mismatched output must fail closed before unguarded graph
  mutation.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Timing attribution showing whether the next graph-facing gate preserves the
  M8d warm no-mutation advantage.
- Task Card, ABI, and ROADMAP updates with allowed and forbidden claims.

## Acceptance Gates

- [x] Reuses the exact M8 selected source pack and records the same canonical
      source-pack SHA.
- [x] Worker row-key output, raw-overlap rehydration, and shadow ledger pass.
- [x] The selected graph-facing binding or object-vector proof passes in
      no-unguarded-mutation mode.
- [x] M8a chain-input oracle pack replay remains `match`.
- [x] Canonical Flye artifacts remain unchanged.
- [x] Timing separates the next graph-facing gate from worker and validation
      costs.
- [x] Negative proof fails closed before unguarded graph mutation.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented by:

- `patches/flye/2.9.6/0059-cuflye-read-to-graph-full-query-hit-binding-object-timing.patch`
- `scripts/run_m8e_selected_graph_binding_object_proof.sh`
- `tests/golden/cuflye-m8e-selected-graph-binding-object-proof-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m8e-proof-20260701T170000Z
fixture=toy-hifi
selected_query_count=16
m8a_selected_quick_overlap_ms=79.294112
m8b_source_pack_sha256=5fb1df86185f3cdce0bc0c15087b7bead53db6d46b523740650d4092a89c25aa
source_pack_raw_overlap_records=27
source_pack_chain_input_records=18
positive_binding_rows=18
positive_live_graph_edge_rows=18
positive_object_vector_rows=18
positive_object_accounting_rows=18
warm_graph_edge_binding_avg_ms=0.05335466666666666
warm_object_vector_smoke_avg_ms=0.061664
warm_graph_facing_validation_total_avg_ms=0.313323
warm_no_mutation_seam_total_avg_ms=66.49926666666666
warm_no_mutation_seam_speedup_vs_m8a=1.1924058109913995
negative_object_status=object-vector-smoke-failed-before-graph-mutation
negative_object_binding_status=passed
negative_object_smoke_status=failed
negative_object_graph_mutation_consumed_worker_output=false
summary_checks_passed=25/25
```

Plain-language benefit:

M8e shows that the selected CUDA path can produce rows that survive the next
Flye-facing object gate: `18` selected rows bind to live `GraphEdge` objects and
become `18` checked object-vector smoke rows. The extra gate cost is small
(`0.053 ms` binding plus `0.062 ms` object-vector smoke on warm requests), so
the warm no-mutation seam remains faster than the matched CPU quick-overlap
baseline: `66.499267 ms` vs `79.294112 ms`, or `1.192x`.

M8e still does not prove default GPU mode, unguarded graph mutation,
object-vector substitution, full non-key raw-overlap field parity, or whole-Flye
speedup.
