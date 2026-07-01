# Task Card: cuFlye M6i Parallel Full Query-Hit Replay Benchmark

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M6h correctness-only CUDA full-query-hit replay consumer into a
parallel benchmark target, while preserving canonical M6g row-key parity and
fail-closed behavior.

## In Scope

- Keep the M6h source-pack input and canonical row-key diff gate.
- Replace or augment the one-thread-per-ext-group CUDA DP with a more parallel
  predecessor scoring strategy for supported groups.
- Preserve deterministic CUDA A/B output after canonical row-key comparison.
- Record CPU replay timing, CUDA kernel timing, and CUDA total timing on the
  same selected pack.
- Decide whether the parallel kernel is ready for a Flye-side dry-run seam or
  whether the next bottleneck is worker/session overhead.

## Out of Scope

- No Flye graph mutation.
- No default GPU mode.
- No claim about full non-key raw-overlap field parity.
- No speed claim unless CUDA beats a matched CPU baseline for the same bounded
  work.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse `cuda/cuflye_cuda_raii.hpp` for device resources.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs outside approved low-level RAII wrappers.
- Unsupported shapes must fail closed and report the rejected input shape.
- Keep row-key ordering deterministic or compare through an explicit canonical
  sort/diff gate.

## Deliverables

- Updated CUDA full-query-hit replay implementation or a separate benchmark
  mode under `cuda/`.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded performance conclusion.

## Acceptance Gates

- [x] M6h canonical CPU-vs-CUDA row-key parity still passes.
- [x] CUDA A/B row-key diff remains `match`.
- [x] Unsupported-shape fail-closed proof still passes.
- [x] Matched CPU and CUDA timings are recorded.
- [x] Any speedup claim is supported by the matched timing data; otherwise the
      Task Card explicitly says there is no speed benefit yet.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

M6i adds `--kernel-mode serial|parallel-score` to the standalone CUDA
full-query-hit replay consumer. `serial` preserves the M6h one-thread-per-group
kernel. `parallel-score` uses `128` CUDA threads per active ext group to split
the predecessor scoring scan inside each DP row, then keeps DP backtracking,
overlap geometry checks, sorting, and primary-overlap filtering serial inside
the block to minimize semantic risk.

DGX proof:

```text
proof_root=/tmp/cuflye-m6i-proof-20260701T072117Z
golden=tests/golden/cuflye-m6i-parallel-full-query-hit-replay-benchmark-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_status=match
cpu_row_key_exact_match=true
serial_kernel_mode=serial
parallel_kernel_mode=parallel-score
parallel_threads=128
cpu_vs_serial_row_key_diff=match
cpu_vs_parallel_row_key_diff=match
serial_vs_parallel_row_key_diff=match
parallel_ab_row_key_diff=match
unsupported_exit_status=2
unsupported_json_status=error
unsupported_error="required bytes exceed memory budget"
cpu_replay_wall_seconds=0.11
serial_cuda_wall_seconds=0.48
parallel_cuda_wall_seconds=0.43
serial_kernel_ms=53.287348
parallel_kernel_ms=52.542531
parallel_kernel_speedup_vs_serial_kernel=1.0141755066957092
parallel_total_speedup_vs_serial_total=1.148385663790127
```

Plain-language benefit:

```text
M6i proves that the full-query-hit CUDA replay can start using real GPU
parallelism without changing the canonical row-key output. The gain is small on
this tiny pack: parallel-score improves kernel time from 53.287348 ms to
52.542531 ms and cold CUDA wall time from 0.48 s to 0.43 s, but CPU replay is
still about 0.11 s. The next ROI is not more micro-kernel tuning; it is a warm
session/worker path that removes repeated CUDA process and context overhead.
```
