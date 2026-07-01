# Task Card: cuFlye M8b Full-Query-Hit Source Pack for M8a Target

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Run the existing full-query-hit source-pack and warm CUDA replay path on the
M8a selected quick-overlap target, so any CUDA speed claim is measured against
the same Flye CPU quick-overlap baseline.

M8a selected 16 replayable query ids with `79.294112 ms` of Flye CPU
quick-overlap work. M8b should decide whether the M6j-style warm CUDA
full-query-hit session can beat that exact target.

## In Scope

- Capture a full-query-hit source pack for the M8a selected query ids.
- Validate source-pack completeness and run CPU full-query-hit replay.
- Run the existing CUDA full-query-hit replay warm-session path against the
  same selected pack.
- Compare CPU replay, CUDA replay, M8a M6b chain-input pack, and Flye
  canonical artifacts.
- Record whether hot CUDA request time is below the selected Flye CPU
  quick-overlap baseline.

## Out of Scope

- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.
- No unsupported shape expansion unless the selected M8a pack fails closed and
  a narrower supported pack is explicitly recorded.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing CUDA full-query-hit replay worker/session code and RAII
  wrappers.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep row-key and chain-input comparisons deterministic through canonical
  diff gates.
- Unsupported source-pack shapes must fail closed without silent CPU fallback.

## Deliverables

- DGX full-query-hit source-pack proof for the M8a selected query ids.
- CPU replay and CUDA warm-session timing summary.
- Golden proof manifest under `tests/golden/`.
- ROADMAP and Task Card updates stating whether M8b proves a bounded hot-path
  CUDA advantage against the matched Flye quick-overlap baseline.

## Acceptance Gates

- [x] Full-query-hit source pack captures exactly the M8a selected query ids or
      records a fail-closed narrowed target.
- [x] CPU source-pack replay reaches accepted row-key parity for the selected
      pack.
- [x] CUDA replay row-key diff matches CPU replay.
- [x] M8a chain-input oracle pack replay remains `match`.
- [x] Flye canonical artifacts match CPU golden with capture enabled.
- [x] Hot CUDA request time is compared against
      `selected_quick_overlap_ms=79.294112`; any speed claim is limited to this
      bounded hot path.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed in M8b.

DGX proof:

```text
proof_root=/tmp/cuflye-m8b-proof-20260701T210000Z
golden=tests/golden/cuflye-m8b-full-query-hit-source-pack-for-m8a-target-dgx-aarch64.json
selected_query_count=16
selected_query_ids=2145,2160,2146,2152,2161,2167,2148,2154,2157,2163,2165,2149,84,2150,5,361
m8a_selected_quick_overlap_ms=79.294112
source_pack_status=ok
source_pack_canonical_sha256=5fb1df86185f3cdce0bc0c15087b7bead53db6d46b523740650d4092a89c25aa
source_pack_full_query_hit_records=15306
source_pack_ext_groups=47
source_pack_raw_overlap_records=27
source_pack_chain_input_records=18
cpu_replay_status=match
cpu_replay_row_key_exact_match=true
cpu_replay_wall_ms=254.6812379732728
cuda_confirm_runs=cuda-c,cuda-d
cuda_combined_warm_request_count=18
cuda_combined_warm_request_mean_ms=63.471744111111114
cuda_combined_warm_request_best_ms=63.469872
cuda_combined_warm_requests_below_m8a_baseline=18/18
cuda_speedup_vs_m8a_quick_overlap_mean=1.2492820720538398
cuda_speedup_vs_m8a_quick_overlap_best=1.2493189209519753
cpu_vs_cuda_c_row_key_diff=match
cpu_vs_cuda_d_row_key_diff=match
cuda_c_vs_cuda_d_row_key_diff=match
capture_vs_control_canonical_artifacts=match
required_hot_speed_gate_passed=true
preferred_1_25x_gate_passed=false
```

M8b proves a bounded hot-path CUDA advantage at the selected full-query-hit
replay boundary: confirmed warm CUDA requests average `63.471744 ms`, below the
matched Flye quick-overlap baseline of `79.294112 ms`, while preserving
canonical raw-overlap row-key parity. It does not prove default GPU mode,
graph consumption, full non-key raw-overlap parity, or whole-Flye speedup.
