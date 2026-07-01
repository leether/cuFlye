# Task Card: cuFlye M6n File-Backed Full Query-Hit Worker Session

Status: complete

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move beyond M6m's intra-process JSONL warm lifecycle by adding a true
file-backed full-query-hit worker session so separate Flye seam calls can reuse
one already-running CUDA worker process.

## In Scope

- Define a bounded `full-query-hit-session-v0` request/response contract.
- Start or attach to a long-lived CUDA full-query-hit worker session in proof
  mode.
- Submit at least two separate actual requests to the same live worker process.
- Prove the second request is warm without relaunching the worker binary.
- Preserve the M6m row-key oracle gate and
  `graph_mutation_consumed_worker_output=false`.
- Keep worker startup, attach, request, and teardown timing separated.
- Keep unsupported session state, worker failures, stale response files, and
  mismatched output fail-closed before graph mutation.

## Out of Scope

- No graph mutation from worker output.
- No default GPU mode.
- No whole-Flye speed claim until end-to-end worker wall time improves.
- No full non-key raw-overlap parity claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and minimal.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Keep direct CUDA resource management inside CUDA worker code and existing RAII
  wrappers.
- Worker output must pass the row-key oracle gate before any eligibility flag is
  set.

## Deliverables

- Session protocol documentation under `docs/abi/`.
- Flye-side proof seam for file-backed full-query-hit worker sessions.
- CUDA worker session proof mode or helper compatible with the protocol.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded session-lifecycle conclusion.

## Acceptance Gates

- [x] Two separate Flye seam submissions attach to one live worker session.
- [x] The second actual request reports `worker_cuda_context_warm=true`.
- [x] The second actual request avoids source parsing, device allocation, and
      host-to-device copy in worker timing.
- [x] Row-key diff matches the CPU raw-overlap oracle for every validated
      actual request.
- [x] Negative stale-session or memory-budget proof fails closed before graph
      mutation.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented by:

- `cuda/cuflye_cuda_full_query_hit_replay.cu`
- `scripts/run_flye_fixture.sh`
- `patches/flye/2.9.6/0044-cuflye-read-to-graph-full-query-hit-worker-session-file.patch`
- `docs/abi/full-query-hit-worker-session-v0.md`
- `tests/golden/cuflye-m6n-file-backed-full-query-hit-worker-session-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m6n-proof-20260701T085823Z
fixture=toy-hifi
query_ids=5,6,7,8,9,10,11,12
positive_session_processed_requests=2
first_request_id=read-to-graph-full-query-hit-session-cuflye-m6n-proof-20260701T085823Z_positive-first_worker
second_request_id=read-to-graph-full-query-hit-session-cuflye-m6n-proof-20260701T085823Z_positive-second_worker
first_worker_wall_ms=100.728
first_request_total_ms=98.495
first_worker_cuda_context_warm=false
second_worker_wall_ms=55.4038
second_request_total_ms=52.735775
second_worker_cuda_context_warm=true
second_parse_ms=0.0
second_device_allocation_ms=0.0
second_host_to_device_ms=0.0
first_row_key_diff=match
second_row_key_diff=match
negative_status=failed-before-graph-mutation
negative_error="CUDA full-query-hit worker session request failed: required bytes exceed memory budget"
negative_graph_mutation_consumed_worker_output=false
default_cpu_artifact_hashes_match_m0=true
```

Plain-language benefit:

```text
M6n turns the warm full-query-hit worker proof into a true file-backed session
that separate Flye seam runs can attach to. The second request reuses the same
live CUDA worker and drops from about 100.728 ms wall / 98.495 ms request time
to about 55.404 ms wall / 52.736 ms request time. This is still dry-run and
does not mutate Flye graph state, but it proves cross-Flye-call worker reuse
instead of only an in-process JSONL warmup.
```

Next highest-ROI task:

```text
M6o: add a session-scale/performance gate that submits several selected
full-query-hit windows through one file-backed worker session, records
amortized cold-vs-warm timing, and decides whether the next guarded
graph-consumption step has enough ROI to proceed.
```
