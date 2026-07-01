# Task Card: cuFlye M6k Full Query-Hit Worker Seam

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Convert the M6j `--repeat-count` warm benchmark into a real full-query-hit
worker or Flye-side dry-run seam so the bounded hot-path advantage can be
requested through an integration boundary instead of an in-process benchmark
loop.

## In Scope

- Add a request/response boundary for the M6j `parallel-score` replay path.
- Preserve explicit metadata: schema, kernel mode, device, request ordinal,
  timing, source-pack shape, output path, and error status.
- Keep the M6j selected source pack as the first supported shape.
- Preserve CPU-vs-worker row-key parity, worker A/B determinism, and
  fail-closed unsupported-shape behavior.
- Compare cold process, warm worker request, and CPU replay timing on the same
  selected pack.

## Out of Scope

- No Flye graph mutation.
- No default GPU mode.
- No larger source-pack shape expansion.
- No full non-key raw-overlap parity claim.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse `cuda/cuflye_cuda_raii.hpp` for device resources and any worker-level
  CUDA ownership.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs outside approved low-level RAII wrappers.
- Request failures must be fail-closed with explicit metadata.
- Worker output must be deterministic or checked through canonical row-key diff.

## Deliverables

- Full-query-hit worker or Flye-side dry-run seam.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded worker-boundary conclusion.

## Acceptance Gates

- [x] Worker/Flye-seam output row-key diff matches CPU replay.
- [x] Worker A/B row-key diff remains `match`.
- [x] Unsupported-shape fail-closed proof passes through the worker boundary.
- [x] Warm worker request timing preserves the M6j bounded hot-path advantage
      within the same selected source-pack shape.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

M6k adds a file-backed full-query-hit worker protocol to
`cuflye-cuda-full-query-hit-replay`:

- `--worker-request-json PATH` processes one request and writes a response.
- `--worker-requests-jsonl PATH` processes at least two requests in one worker
  process, preserving CUDA context and device buffers for later requests.
- The first JSONL request is cold; later compatible requests are warm and
  report `worker_cuda_context_warm=true`.

The worker supports only the current selected source-pack shape and
`parallel-score` kernel mode. Unsupported requests fail closed with an explicit
`cuflye-full-query-hit-worker-response-v0` error response.

DGX proof:

```text
proof_root=/tmp/cuflye-m6k-proof-20260701T074410Z
golden=tests/golden/cuflye-m6k-full-query-hit-worker-seam-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_status=match
cpu_row_key_exact_match=true
cpu_replay_wall_ms=110.0
cold_parallel_wall_ms=490.0
cold_parallel_total_ms=356.641602
worker_a_actual_request_ordinal=2
worker_a_actual_cuda_context_warm=true
worker_a_actual_request_ms=52.243993
worker_a_actual_kernel_ms=52.177993
worker_a_actual_parse_ms=0.0
worker_a_actual_device_allocation_ms=0.0
cpu_vs_worker_a_row_key_diff=match
cold_vs_worker_a_row_key_diff=match
worker_ab_row_key_diff=match
unsupported_exit_status=1
unsupported_json_status=error
unsupported_error="required bytes exceed memory budget"
bounded_warm_worker_speedup_vs_cpu_replay_wall=2.105505220475778
```

Plain-language benefit:

```text
M6k turns the M6j warm benchmark into a real file-backed worker boundary. The
second worker request no longer pays parse, allocation, or host-to-device setup
cost, and it keeps the same row-key output as CPU. On this bounded selected
pack, the warm worker request is about 52.244 ms versus 110 ms for matched CPU
replay, a 2.11x hot-request win. This is still not a cold-process or whole-Flye
speedup claim.
```
