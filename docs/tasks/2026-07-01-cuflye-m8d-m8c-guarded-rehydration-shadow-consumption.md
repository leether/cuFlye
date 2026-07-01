# Task Card: cuFlye M8d M8c Guarded Rehydration Shadow Consumption

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M8c selected worker/session seam one step closer to graph-facing
Flye code by adding an M8b/M8c-specific guarded rehydration or shadow
consumption proof.

M8c showed that warm Flye seam wall time remains faster than the matched
CPU quick-overlap baseline before graph mutation. M8d should measure whether
the graph-facing validation and rehydration layer preserves that bounded
advantage when using the same selected source pack and fail-closed contract.

## In Scope

- Reuse the exact M8b/M8c selected full-query-hit source pack and query ids.
- Reuse the `session-file-v0` worker lifecycle and existing Flye-side dry-run
  seam.
- Rehydrate or shadow-consume validated worker rows into the next graph-facing
  representation already used by M6p through M7b.
- Attribute worker session time, row-key diff time, rehydration/shadow ledger
  time, and total no-mutation seam time.
- Keep canonical Flye artifacts unchanged and keep negative proofs fail-closed
  before graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No whole-Flye speed claim.
- No expansion beyond the M8b/M8c selected source-pack shape unless an
  unsupported shape is recorded as a fail-closed result.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing RAII wrappers and graph-facing handoff helpers.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep all worker-derived rows diff-gated before graph-facing conversion.
- Unsupported, incomplete, or mismatched worker output must fail closed before
  any graph mutation path.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Timing attribution for worker session, validation diff, guarded
  rehydration/shadow consumption, and total no-mutation seam time.
- Task Card, ABI, and ROADMAP updates stating whether graph-facing validation
  overhead preserves or erases the M8c seam advantage.

## Acceptance Gates

- [x] Reuses the exact M8b/M8c selected source pack and records the same
      canonical source-pack SHA.
- [x] Worker row-key output matches CPU replay for the selected pack.
- [x] Rehydrated or shadow-consumed graph-facing row counts match the selected
      CPU oracle shape.
- [x] M8a chain-input oracle pack replay remains `match`.
- [x] Canonical Flye artifacts remain unchanged.
- [x] Timing separates worker session, validation diff,
      rehydration/shadow-consumption, and total no-mutation seam cost.
- [x] Negative proof fails closed before graph mutation.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed in M8d.

Implementation:

- Added
  `patches/flye/2.9.6/0058-cuflye-read-to-graph-full-query-hit-graph-facing-timing.patch`
  to expose graph-facing timing fields in the Flye dry-run audit.
- Added `scripts/run_m8d_guarded_shadow_proof.sh` to run the M8b/M8c selected
  source pack through `session-file-v0`, raw-overlap rehydration, and shadow
  ledger gates.

DGX proof:

```text
proof_root=/tmp/cuflye-m8d-proof-20260701T231500Z
golden=tests/golden/cuflye-m8d-m8c-guarded-rehydration-shadow-consumption-dgx-aarch64.json
fixture=toy-hifi
selected_query_count=16
selected_query_ids=2145,2160,2146,2152,2161,2167,2148,2154,2157,2163,2165,2149,84,2150,5,361
m8a_selected_quick_overlap_ms=79.294112
m8b_source_pack_sha256=5fb1df86185f3cdce0bc0c15087b7bead53db6d46b523740650d4092a89c25aa
source_pack_full_query_hit_records=15306
source_pack_raw_overlap_records=27
source_pack_chain_input_records=18
file_session_request_count=4
warm_worker_wall_avg_ms=65.8929
warm_request_total_avg_ms=64.05510933333333
warm_kernel_avg_ms=63.799129666666666
warm_row_key_diff_avg_ms=0.03248033333333333
warm_raw_overlap_rehydration_avg_ms=0.09726966666666666
warm_raw_overlap_shadow_ledger_avg_ms=0.07991
warm_graph_facing_validation_total_avg_ms=0.20966000000000004
warm_no_mutation_seam_total_avg_ms=66.1026
warm_no_mutation_seam_speedup_vs_m8a=1.1995611670342772
all_no_mutation_seam_speedup_vs_m8a=1.163573227464275
m8a_chain_input_oracle_replay=match
default_cpu_artifacts=match
negative_memory_status=failed-before-graph-mutation
negative_ledger_status=shadow-ledger-failed-before-graph-mutation
negative_ledger_rehydration_status=passed
negative_ledger_shadow_status=failed
negative_graph_mutation_consumed_worker_output=false
summary_checks_passed=17/17
```

M8d proves the graph-facing validation layer does not erase the selected CUDA
benefit. Warm no-mutation seam total averages `66.102600 ms`, below the matched
CPU quick-overlap baseline of `79.294112 ms`, for `1.200x` bounded speedup.

M8d still does not prove default GPU mode, unguarded graph mutation,
GraphEdge object-vector consumption, full non-key raw-overlap field parity, or
whole-Flye speedup.
