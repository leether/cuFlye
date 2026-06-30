# Task Card: cuFlye M1j CUDA Candidate Core Benchmark

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Establish the first bounded performance win for CUDA over CPU in cuFlye's
candidate-generation lane.

The core question this card must answer is:

```text
Can CUDA count candidate lookup-key matches faster than the CPU oracle for the same synthetic query/index pair space?
```

## Background

M1f through M1i built correctness gates: ABI output, equality join, k-mer
encoding, standard-form lookup keys, and read-window query generation. M1j adds
a focused benchmark for the parallel candidate scan itself.

## In Scope

- Add a standalone CUDA candidate-core benchmark.
- Generate deterministic query and index lookup-key arrays.
- Compute CPU match count and timings.
- Compute CUDA match count and timings.
- Prove CPU and CUDA counts match.
- Record kernel-only and total CUDA speedups.
- Validate on DGX.

## Out of Scope

- Full Flye benchmark.
- Candidate TSV serialization benchmark.
- Full `VertexIndex` construction.
- CPU chaining, graph construction, or polishing.
- Multi-GPU optimization.

## Deliverables

- `cuda/cuflye_cuda_candidate_core_bench.cu`
- `scripts/build_cuda_candidate_core_bench.sh`
- `docs/abi/cuda-candidate-core-bench-v0.md`
- DGX proof manifest showing matched counts and speedup

## Acceptance Gates

- Benchmark builds on DGX with `nvcc`.
- Runtime JSON validates with `python3 -m json.tool`.
- CPU and CUDA match counts are identical.
- `speedup_cpu_vs_gpu_kernel_best > 1`.
- `speedup_cpu_vs_gpu_total_best > 1`.
- Proof records benchmark dimensions, trials, timings, and scope caveat.

## Execution Checklist

- [ ] Add CUDA candidate-core benchmark source.
- [ ] Add build script.
- [ ] Add ABI/benchmark contract doc.
- [ ] Build benchmark on DGX with `nvcc`.
- [ ] Run benchmark on DGX.
- [ ] Verify matched counts.
- [ ] Verify CUDA speedup over CPU.
- [ ] Record compact proof and close this card.

## Merge Note

Pending implementation.
