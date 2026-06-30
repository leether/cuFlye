# Task Card: cuFlye M4g Batched Overlap Worker

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build a single-process batched overlap-chain worker so multiple real replay
fixtures can share one CUDA context and reuse allocations.

The core question this card must answer is:

```text
Can a long-lived batched overlap-chain worker make CUDA faster than CPU over a
real replay-match fixture batch while preserving per-query overlap-range-v1
hashes?
```

## Background

M4f generated real batched overlap-chain fixtures and proved top 9 replay-match
fixtures validate across CPU, serial CUDA, and parallel CUDA modes. It also
showed the current external per-fixture CUDA invocation is slower than CPU:
CPU total mean `12.300116 ms`, serial CUDA `38.801200 ms`, parallel CUDA
`47.293990 ms`.

The measured blocker is not fixture scarcity anymore. The next blocker is
process/context/allocation overhead and lack of real multi-query work inside one
CUDA execution boundary.

## In Scope

- Add a single-process batch mode or worker for overlap replay fixtures.
- Reuse CUDA context and device buffers across multiple fixture requests.
- Emit per-fixture overlap TSVs or a combined output with unambiguous provenance.
- Validate every fixture output as `overlap-range-v1`.
- Canonical-diff every fixture output against its oracle.
- Benchmark CPU batch, serial CUDA batch, and best CUDA batch mode.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No Flye graph integration.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No synthetic fixture duplication as a speed claim.
- No workload-level Flye GPU mode claim.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Reuse existing RAII helpers for CUDA allocations and events.
- Do not introduce direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`, or
  `cudaEventDestroy` outside approved RAII wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep batch provenance explicit in JSON output.
- Fail closed on unsupported or replay-mismatch fixtures unless explicitly run
  in audit mode.

## Deliverables

- Single-process batch mode or worker.
- DGX proof over the M4f top replay-match fixtures.
- Timing comparison against M4f's external per-fixture runner.
- Updated roadmap claim boundaries based on measured result.

## Acceptance Gates

- Every selected fixture output validates as `overlap-range-v1`.
- Every selected fixture output canonical-diffs `match` against its oracle.
- CUDA context setup is separated from warm batch hotpath timing.
- Device allocations are reused where shapes permit, or non-reuse is recorded.
- If CUDA batch is faster than CPU batch, the claim is scoped to the M4f real
  replay-match batch.
- If CUDA batch is not faster, proof records the remaining bottleneck.
- Local syntax/style gates pass.
- CUDA ownership scan shows no new direct resource APIs outside RAII wrappers.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [ ] Design batch input/output contract and provenance.
- [ ] Implement single-process CPU and CUDA batch modes.
- [ ] Reuse CUDA context and buffers across compatible fixture shapes.
- [ ] Validate per-fixture outputs on DGX.
- [ ] Diff per-fixture outputs against oracles.
- [ ] Record timing summary and speed ratios.
- [ ] Run ownership/resource scan.
- [ ] Record compact DGX proof and close this card.
