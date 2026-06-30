# Task Card: cuFlye M4e Overlap Chain Parallel Reduction

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Improve the M4c/M4d CUDA overlap-chain prototype by increasing GPU occupancy
inside each target group while preserving exact `overlap-range-v1` output.

The core question this card must answer is:

```text
Can a group-internal parallel reduction kernel make the bounded CUDA
overlap-chain hotpath faster than the M4d CPU baseline without changing overlap
semantics?
```

## Background

M4d proved CPU/CUDA correctness parity and added a fair hotpath benchmark. It
also showed the current CUDA kernel is slower for the only supported fixture:
CPU mean hotpath `2.330413 ms`, CUDA mean hotpath `4.721515 ms`.

The main technical reason is low occupancy: the M4c/M4d kernel launches one
block per target group and only one active thread per block. The supported
fixture has `120` target groups, a maximum group size of `363`, and a median
group size of `14`; this is not enough work to hide GPU overhead.

## In Scope

- Add an explicit CUDA kernel mode such as `serial` and `parallel-reduce`.
- Parallelize the DP predecessor search inside each target group while
  preserving Flye's tie-break and early-stop semantics.
- Keep the existing serial CUDA kernel available as a correctness reference.
- Benchmark CPU baseline, serial CUDA, and parallel-reduce CUDA on DGX.
- Validate and canonical-diff every output against the M4b oracle.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No Flye graph integration.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No synthetic speedup claim from duplicated fixtures unless explicitly labeled
  as synthetic.
- No broad workload-level speedup claim from the single M4b fixture.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Reuse existing RAII helpers for CUDA allocations and events.
- Do not introduce direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`, or
  `cudaEventDestroy` outside approved RAII wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Make kernel mode explicit in CLI and JSON output.
- Fail closed on unsupported fixture shapes and memory-budget violations.

## Deliverables

- Parallel-reduction CUDA kernel mode for the supported fixture shape.
- Benchmark output comparing CPU, serial CUDA, and parallel-reduce CUDA.
- DGX proof manifest under `tests/golden/`.
- Roadmap claim update based on measured speed ratio.

## Acceptance Gates

- Serial CUDA output still validates and matches the oracle.
- Parallel-reduce CUDA output validates and matches the oracle.
- CPU baseline output validates and matches the oracle.
- Benchmark records CPU, serial CUDA, and parallel-reduce CUDA timings.
- If parallel-reduce CUDA is faster than CPU, the claim is scoped to this
  fixture and kernel mode.
- If parallel-reduce CUDA is still not faster, proof records the blocker and
  next target.
- Local syntax/style gates pass.
- CUDA ownership scan shows no new direct resource APIs outside RAII wrappers.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [ ] Inspect M4d benchmark and group-size distribution.
- [ ] Add explicit CUDA kernel mode option.
- [ ] Implement group-internal parallel predecessor reduction.
- [ ] Validate serial and parallel-reduce outputs on DGX.
- [ ] Diff CPU, serial CUDA, and parallel-reduce CUDA outputs against the M4b
  oracle.
- [ ] Record benchmark speed ratios.
- [ ] Run ownership/resource scan.
- [ ] Record compact DGX proof and close this card.
