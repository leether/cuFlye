# Task Card: cuFlye M6o Session Scale Performance Gate

Status: complete

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Measure whether the M6n file-backed full-query-hit worker session keeps its
advantage when more than two selected Flye seam requests are submitted through
one live worker.

## In Scope

- Reuse the M6n `session-file-v0` protocol without changing graph state.
- Submit several compatible selected full-query-hit windows through one worker
  session.
- Record cold request, warm request, amortized per-request timing, and row-key
  diff results.
- Include at least one incompatible or memory-budget negative proof that fails
  closed.
- Decide whether the next guarded graph-consumption step has enough measured
  ROI to proceed.

## Out of Scope

- No default GPU mode.
- No graph mutation from worker output.
- No full raw-overlap non-key parity claim.
- No new CUDA kernel unless the session-scale proof shows the current kernel is
  no longer the limiting risk.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Prefer proof harness and manifest changes before adding new C++ code.
- Keep Flye patches C++11-compatible if any seam code changes are required.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Keep all new modes explicit, opt-in, deterministic, and fail-closed.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Updated ROADMAP conclusion with cold, warm, and amortized timing.
- Any runner-script support needed to repeat session submissions safely.
- Next Task Card based on the measured ROI.

## Acceptance Gates

- [x] One file-backed worker session processes at least four compatible actual
      requests.
- [x] Every warm request reports `worker_cuda_context_warm=true`.
- [x] Warm requests report zero parse, device allocation, and host-to-device
      copy timing.
- [x] Row-key diff matches the CPU raw-overlap oracle for every validated
      actual request.
- [x] Negative proof fails closed before graph mutation.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented by:

- `scripts/run_m6o_session_scale_proof.sh`
- `tests/golden/cuflye-m6o-session-scale-performance-gate-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m6o-proof-20260701T090904Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_session_processed_requests=4
request_ordinals=1,2,3,4
cold_worker_wall_ms=60.1647
cold_request_total_ms=57.310081
warm_worker_wall_avg_ms=55.003433333333334
warm_request_total_avg_ms=52.690358
warm_request_total_min_ms=52.619195
warm_request_total_max_ms=52.744364
warm_kernel_avg_ms=52.52250166666667
amortized_worker_wall_including_cold_ms=56.29375
amortized_request_total_including_cold_ms=53.845288749999995
warm_parse_ms=0.0
warm_device_allocation_ms=0.0
warm_host_to_device_ms=0.0
all_row_key_diffs=match
negative_status=failed-before-graph-mutation
negative_error="CUDA full-query-hit worker session request failed: required bytes exceed memory budget"
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Plain-language benefit:

```text
M6o shows that M6n's file-backed full-query-hit session benefit is stable
across four separate Flye seam submissions. The first request was cold at about
60.165 ms wall / 57.310 ms request time. The next three warm requests averaged
55.003 ms wall / 52.690 ms request time, with parse, device allocation, and
host-to-device copy all at 0 ms. This still does not mutate Flye graph state,
but it proves the session path can amortize worker setup across multiple real
Flye seam calls.
```

Next highest-ROI task:

```text
M6p: design a guarded full-query-hit graph-consumption dry-run that rehydrates
session-validated raw-overlap rows into Flye-side structures without enabling
default GPU mode, then prove mismatch and corruption still fail closed before
graph mutation.
```
