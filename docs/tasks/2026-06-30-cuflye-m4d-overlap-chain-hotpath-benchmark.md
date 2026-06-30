# Task Card: cuFlye M4d Overlap Chain Hotpath Benchmark

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M4c correctness prototype into a fair, repeatable hotpath benchmark
for the supported overlap-chain replay shape.

The core question this card must answer is:

```text
After CUDA context setup is separated from the hot loop, is the CUDA
overlap-chain replay path faster than a CPU baseline for the same bounded
fixture and identical overlap-range-v1 output?
```

## Background

M4c proved that a standalone CUDA prototype can reproduce the M4b CPU replay
oracle for one supported raw-read fixture, but it only measured a single
standalone process run. That timing includes CUDA context setup and does not
include a fair C++ CPU baseline.

The M4b proof directory currently contains only one M4c-supported fixture:
`query_neg71`. M4d must therefore benchmark warm repeated runs of that shape
and explicitly record the fixture-count limitation before claiming any broader
overlap-chain speedup.

## In Scope

- Add a C++ CPU replay baseline for the M4c supported fixture shape.
- Add repeated warm-run timing for the CUDA path without changing output
  semantics.
- Keep output comparison at `overlap-range-v1`.
- Record per-run or aggregate timing for CPU baseline, CUDA setup, CUDA
  host-to-device copy, CUDA kernel, CUDA device-to-host copy, and total hotpath.
- Run the benchmark on DGX against the M4b `query_neg71` fixture.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No Flye graph integration.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No new large replay fixtures committed.
- No broad real-workload speedup claim from a single toy fixture.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Reuse existing RAII helpers for CUDA allocations and events.
- Do not introduce direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`, or
  `cudaEventDestroy` outside approved RAII wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep CPU and CUDA output paths behind explicit backend or benchmark mode
  switches.
- Fail closed on unsupported fixture shapes and memory-budget violations.

## Deliverables

- CPU baseline mode or benchmark mode for the M4c replay prototype.
- Warm-run CUDA timing mode for the same fixture.
- Validation and diff proof that CPU baseline and CUDA benchmark output both
  match the M4b oracle.
- DGX proof manifest under `tests/golden/`.
- Updated roadmap claim boundaries based on the measured result.

## Acceptance Gates

- CPU baseline output validates as `overlap-range-v1`.
- CUDA benchmark output validates as `overlap-range-v1`.
- CPU baseline and CUDA output canonical-diff `match` against the M4b oracle.
- Benchmark separates cold setup from warm hotpath timing.
- If CUDA hotpath is faster, the claim is scoped to this fixture and mode.
- If CUDA hotpath is not faster, the proof records the blocker and next
  optimization target.
- Local syntax/style gates pass.
- CUDA ownership scan shows no new direct resource APIs outside RAII wrappers.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [ ] Inspect M4c timing breakdown and M4b fixture inventory.
- [ ] Add CPU replay baseline for the supported fixture shape.
- [ ] Add warm repeated CUDA benchmark mode.
- [ ] Validate CPU and CUDA benchmark outputs on DGX.
- [ ] Diff CPU and CUDA outputs against the M4b oracle.
- [ ] Record timing summary and speed ratio.
- [ ] Run ownership/resource scan.
- [ ] Record compact DGX proof and close this card.
