# Task Card: cuFlye M8c Flye-Side M8b Worker Session Seam

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M8b bounded hot-path CUDA advantage from standalone replay into the
Flye-side full-query-hit worker/session seam, while still preventing graph
mutation.

M8b proved the selected CUDA replay boundary can beat the same selected Flye
CPU quick-overlap baseline when the worker is warm. M8c should measure the
real seam overhead when Flye submits the M8b selected source pack through the
file-backed worker/session path.

## In Scope

- Reuse the M8b selected full-query-hit source pack and query ids.
- Run the Flye-side full-query-hit worker/session dry-run seam against that
  pack.
- Compare worker output against CPU replay row-key oracle and M8a chain-input
  oracle pack.
- Measure Flye-side submit/poll/request overhead separately from CUDA kernel
  time.
- Preserve canonical Flye artifacts and fail-closed behavior.

## Out of Scope

- No graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.
- No expansion beyond the M8b selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing Flye full-query-hit worker/session seam code.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved RAII wrappers.
- Keep all worker outputs diff-gated by canonical row-key comparison.
- Unsupported or mismatched worker output must fail closed before graph-facing
  consumption.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Timing attribution for Flye submit/poll, worker request total, CUDA kernel,
  and validation diff.
- ROADMAP and Task Card updates that state whether seam overhead preserves or
  erases the M8b standalone hot-path advantage.

## Acceptance Gates

- [x] Flye-side worker/session seam consumes the M8b selected source pack in
      dry-run/no-mutation mode.
- [x] Worker row-key output matches CPU replay for the selected pack.
- [x] M8a chain-input oracle pack replay remains `match`.
- [x] Capture/canonical Flye artifacts remain unchanged.
- [x] Timing separates Flye submit/poll overhead, worker request total, and
      CUDA kernel time.
- [x] Negative proof fails closed before graph-facing consumption.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Completed in M8c.

DGX proof:

```text
proof_root=/tmp/cuflye-m8c-proof-20260701T220000Z
golden=tests/golden/cuflye-m8c-flye-side-m8b-worker-session-seam-dgx-aarch64.json
fixture=toy-hifi
selected_query_count=16
selected_query_ids=2145,2160,2146,2152,2161,2167,2148,2154,2157,2163,2165,2149,84,2150,5,361
m8a_selected_quick_overlap_ms=79.294112
m8b_source_pack_sha256=5fb1df86185f3cdce0bc0c15087b7bead53db6d46b523740650d4092a89c25aa
m8c_source_pack_diff_vs_m8b=match
source_pack_full_query_hit_records=15306
source_pack_raw_overlap_records=27
source_pack_chain_input_records=18
file_session_request_count=4
cold_worker_wall_ms=80.882
cold_request_total_ms=80.066843
warm_worker_wall_avg_ms=65.99733333333333
warm_request_total_avg_ms=64.10740700000001
warm_kernel_avg_ms=63.89005699999999
warm_worker_wall_speedup_vs_m8a_quick_overlap=1.201474483817528
warm_request_total_speedup_vs_m8a_quick_overlap=1.2368947007948705
amortized_worker_wall_speedup_vs_m8a_quick_overlap=1.1373467874380543
worker_wall_minus_request_total_avg_ms=1.8899263333333184
request_total_minus_kernel_avg_ms=0.21735000000002036
m8a_chain_input_oracle_replay=match
default_cpu_artifacts=match
negative_status=failed-before-graph-mutation
negative_error="CUDA full-query-hit worker session request failed: required bytes exceed memory budget"
negative_graph_mutation_consumed_worker_output=false
summary_checks_passed=14/14
```

M8c proves the standalone M8b CUDA advantage survives the Flye-side
worker/session seam in dry-run mode. Warm seam wall time averages
`65.997333 ms`, below the matched Flye quick-overlap baseline of
`79.294112 ms`, for `1.201x` bounded speedup while preserving row-key parity
and fail-closed behavior.

M8c does not prove graph mutation, default GPU mode, full non-key raw-overlap
field parity, production daemon lifecycle, or whole-Flye speedup.
