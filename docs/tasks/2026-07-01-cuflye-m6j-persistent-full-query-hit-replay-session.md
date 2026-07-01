# Task Card: cuFlye M6j Persistent Full Query-Hit Replay Session

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M6i standalone full-query-hit replay binary into a warm session proof
so repeated replay requests avoid cold CUDA process and context setup while
preserving the same canonical row-key parity gates.

## In Scope

- Add a bounded worker/session mode for the M6i source-pack replay path.
- Support the accepted M6i source pack and `parallel-score` kernel mode first.
- Keep request and response metadata explicit: schema, kernel mode, device,
  timing, input shape, output path, and failure status.
- Preserve CPU-vs-CUDA row-key parity, CUDA A/B determinism, and fail-closed
  unsupported-shape behavior.
- Measure cold standalone time, warm session request time, CUDA kernel time,
  and CPU replay time on the same selected pack.

## Out of Scope

- No Flye graph mutation.
- No default GPU mode.
- No new source-pack schema.
- No claim about full non-key raw-overlap field parity.
- No claim that whole Flye is faster.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse `cuda/cuflye_cuda_raii.hpp` for device resources and any session-level
  CUDA ownership.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs outside approved low-level RAII wrappers.
- Keep session failure modes fail-closed; malformed requests, unsupported
  shapes, and memory budget violations must produce explicit error metadata.
- Keep warm-session output deterministic or compare it through the existing
  canonical row-key diff gate.

## Deliverables

- A session-capable full-query-hit replay worker or benchmark harness.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded cold-vs-warm conclusion.

## Acceptance Gates

- [x] M6i CPU-vs-serial and CPU-vs-parallel row-key parity still passes.
- [x] Warm session CUDA A/B row-key diff remains `match`.
- [x] Unsupported-shape fail-closed proof still passes through the session
      path.
- [x] Matched CPU, cold CUDA, and warm-session CUDA timings are recorded.
- [x] Any speedup claim is limited to the measured bounded request shape and is
      supported by the matched timing data.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

M6j adds `--repeat-count N` to the standalone full-query-hit replay binary.
The mode keeps one process, one CUDA context, and one set of device buffers
alive, then executes the same request repeatedly while recording per-request
reset, kernel, device-to-host, and request-total timings. This is a warm
session benchmark harness, not yet a JSONL worker or Flye-side seam.

DGX proof:

```text
proof_root=/tmp/cuflye-m6j-proof-20260701T073041Z
golden=tests/golden/cuflye-m6j-persistent-full-query-hit-replay-session-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_status=match
cpu_row_key_exact_match=true
cpu_replay_wall_ms=90.0
cold_parallel_kernel_mode=parallel-score
cold_parallel_repeat_count=1
cold_parallel_wall_ms=470.0
cold_parallel_total_ms=355.993331
session_parallel_repeat_count=5
session_warm_request_total_best_ms=52.199131
session_warm_request_total_mean_ms=52.200286750000004
session_warm_kernel_best_ms=52.174907
cpu_vs_session_row_key_diff=match
cold_vs_session_row_key_diff=match
session_ab_row_key_diff=match
unsupported_exit_status=2
unsupported_json_status=error
unsupported_repeat_count=5
bounded_hot_request_speedup_vs_cpu_replay_wall=1.7241666341150392
```

Plain-language benefit:

```text
M6j finally gives a scoped GPU-wins-CPU result for this boundary. If we keep
the CUDA process and device buffers warm, one bounded full-query-hit replay
request takes about 52.199 ms versus about 90 ms for the matched CPU replay,
or about 1.72x faster. The cold CUDA process is still slower, so this is a
hot-path/session advantage, not a whole-Flye speedup claim.
```
