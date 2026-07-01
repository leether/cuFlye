# Task Card: cuFlye M6i Parallel Full Query-Hit Replay Benchmark

Status: proposed

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

- [ ] M6h canonical CPU-vs-CUDA row-key parity still passes.
- [ ] CUDA A/B row-key diff remains `match`.
- [ ] Unsupported-shape fail-closed proof still passes.
- [ ] Matched CPU and CUDA timings are recorded.
- [ ] Any speedup claim is supported by the matched timing data; otherwise the
      Task Card explicitly says there is no speed benefit yet.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
