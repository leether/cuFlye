# Task Card: cuFlye M4f Overlap Chain Batched Fixtures

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move overlap-chain CUDA benchmarking from one small query to a real batched
multi-query workload so GPU occupancy can be evaluated honestly.

The core question this card must answer is:

```text
Can we collect or derive multiple real M4c-supported overlap-chain fixtures and
benchmark them as one batch while preserving exact overlap-range-v1 output?
```

## Background

M4d and M4e proved exact CPU/CUDA parity for the only M4c-supported fixture in
the M4b proof directory. They also proved the single-query CUDA path is slower
than the C++ CPU baseline.

The supported fixture is too small for a meaningful GPU speedup: `120` target
groups, max group size `363`, median group size `14`. M4e's group-internal
parallel reduction preserved correctness but became slower because Flye's
early-break semantics still require serial boundary work and block
synchronization dominates.

The next highest-ROI path is not more single-query micro-optimization. It is to
increase real concurrent work by collecting multiple supported overlap-chain
fixtures or adding a bounded batch runner over real fixtures.

## In Scope

- Audit the existing overlap replay dump path to understand why M4b captured
  only one supported fixture.
- Generate or collect additional real supported fixtures if available from the
  toy/raw run or a small sampled run.
- Add a batch manifest or batch runner that consumes multiple fixture
  directories without committing large TSVs.
- Benchmark CPU, serial CUDA, and best CUDA kernel mode over the batch.
- Validate every per-query output as `overlap-range-v1` and canonical-diff
  against its CPU oracle.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No synthetic fixture duplication as a performance claim.
- No Flye graph integration.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No broad workload-level speedup claim unless the batch is real and
  source-described.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Reuse existing RAII helpers for CUDA allocations and events.
- Do not introduce direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`, or
  `cudaEventDestroy` outside approved RAII wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Make synthetic data impossible to confuse with real fixture data.
- Fail closed on unsupported fixture shapes.

## Deliverables

- Batch fixture inventory or explanation of why additional supported fixtures
  are not available from the current run.
- Batch runner or manifest tooling if real supported fixtures are available.
- DGX proof manifest under `tests/golden/`.
- Updated roadmap claim boundaries based on measured batch result.

## Acceptance Gates

- Every batched fixture has a manifest and CPU oracle.
- Unsupported shapes are excluded or fail closed with reasons.
- CPU and CUDA outputs validate as `overlap-range-v1`.
- CPU and CUDA outputs canonical-diff `match` per fixture.
- Benchmark reports total and per-query timing.
- Any speed claim is scoped to the real batch only.
- Local syntax/style gates pass.
- CUDA ownership scan shows no new direct resource APIs outside RAII wrappers.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [ ] Audit M4b replay dump coverage and fixture-selection constraints.
- [ ] Identify or generate additional real supported fixtures.
- [ ] Add batch manifest/runner if supported fixtures exist.
- [ ] Run CPU/CUDA batch validation and diff on DGX.
- [ ] Record timing summary and speed ratios.
- [ ] Run ownership/resource scan.
- [ ] Record compact DGX proof and close this card.
