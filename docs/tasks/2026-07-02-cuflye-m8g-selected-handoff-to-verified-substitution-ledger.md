# Task Card: cuFlye M8g Selected Handoff To Verified Substitution Ledger

Status: completed

Created: 2026-07-02

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M8 selected handoff contract one step closer to a guarded replacement
decision by comparing it with the verified substitution or bypass-plan ledger
shape that later graph-facing milestones expect.

M8f proved that `18` selected object-vector rows can become a deterministic
no-mutation handoff contract while preserving the selected CUDA advantage.
M8g should prove whether that contract can be checked against a later
verified-substitution ledger for the same M8 selected source pack, still
without enabling unguarded graph mutation.

## In Scope

- Reuse the exact M8 selected source pack and query ids.
- Keep `session-file-v0`, row-key diff, raw-overlap rehydration, shadow
  ledger, graph-edge binding, object-vector smoke, and substitution-guard gates
  enabled.
- Add a selected verified-substitution ledger comparison after the M8f handoff
  contract passes.
- Record row-key/order parity, selected ledger rows, and CPU-owned residual
  accounting if the later bypass-plan shape is needed.
- Attribute ledger comparison timing separately from worker, prior
  graph-facing gates, and no-mutation seam total.
- Add a negative proof fault that corrupts the verified substitution ledger and
  fails closed before graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No actual object-vector substitution into Flye graph update logic.
- No selected CPU skip unless the ledger is proven first.
- No whole-Flye speed claim.
- No expansion beyond the M8 selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing graph-facing object helpers, verified-substitution helpers,
  and non-owning `GraphEdge*` conventions.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep every worker-derived ledger behind row-key, rehydration, shadow-ledger,
  graph-edge binding, object-vector, handoff, and verified-ledger gates.
- Unsupported or mismatched output must fail closed before graph mutation.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- ABI notes or ABI updates for the selected handoff to verified-ledger
  comparison.
- Timing attribution showing whether the verified-ledger comparison preserves
  the M8f warm no-mutation advantage.
- Task Card, ABI, and ROADMAP updates with allowed and forbidden claims.

## Acceptance Gates

- [x] Reuses the exact M8 selected source pack and records the same canonical
      source-pack SHA.
- [x] Worker row-key output, raw-overlap rehydration, shadow ledger,
      graph-edge binding, object-vector smoke, and substitution guard pass.
- [x] Verified substitution or bypass-plan ledger rows match the M8f handoff
      rows by row key and deterministic order.
- [x] M8a chain-input oracle pack replay remains `match`.
- [x] Canonical Flye artifacts remain unchanged.
- [x] Timing separates verified-ledger comparison from worker, handoff, and
      prior graph-facing gate costs.
- [x] Negative verified-ledger proof fails closed before unguarded graph
      mutation.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented by:

- `patches/flye/2.9.6/0061-cuflye-read-to-graph-full-query-hit-verified-substitution-timing.patch`
- `scripts/run_m8g_selected_handoff_verified_substitution_ledger.sh`
- `tests/golden/cuflye-m8g-selected-handoff-verified-substitution-ledger-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m8g-proof-20260702T010000Z
fixture=toy-hifi
selected_query_count=16
m8a_selected_quick_overlap_ms=79.294112
m8b_source_pack_sha256=5fb1df86185f3cdce0bc0c15087b7bead53db6d46b523740650d4092a89c25aa
source_pack_raw_overlap_records=27
source_pack_chain_input_records=18
positive_handoff_rows=18
positive_verified_cpu_handoff_rows=18
positive_verified_would_substitute_rows=18
positive_verified_substitution_ledger_rows=18
positive_verified_row_key_matched=true
positive_verified_ordered_row_key_matched=true
warm_handoff_contract_avg_ms=0.05359466666666667
warm_verified_substitution_avg_ms=0.13650166666666666
warm_graph_facing_validation_total_avg_ms=0.47810166666666665
warm_no_mutation_seam_total_avg_ms=66.94503333333334
warm_no_mutation_seam_speedup_vs_m8a=1.1844659424572694
negative_verified_status=verified-substitution-smoke-failed-before-graph-mutation
negative_verified_rehydration_status=passed
negative_verified_shadow_status=passed
negative_verified_binding_status=passed
negative_verified_object_status=passed
negative_verified_guard_status=passed
negative_verified_substitution_status=failed
negative_verified_graph_mutation_consumed_worker_output=false
summary_checks_passed=36/36
```

Plain-language benefit:

M8g shows that the selected CUDA path can take the guarded M8f handoff and
prove its verified-substitution ledger matches the CPU-selected handoff by row
key and deterministic order. The verified ledger comparison costs about
`0.137 ms` on warm requests, and the warm no-mutation seam remains faster than
the matched CPU quick-overlap baseline: `66.945033 ms` vs `79.294112 ms`, or
`1.184x`.

M8g still does not prove default GPU mode, unguarded graph mutation, actual
object-vector substitution into Flye graph update logic, selected CPU bypass,
full non-key raw-overlap field parity, or whole-Flye speedup.
