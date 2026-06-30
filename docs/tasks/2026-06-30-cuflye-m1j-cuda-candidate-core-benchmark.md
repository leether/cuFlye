# Task Card: cuFlye M1j CUDA Candidate Core Benchmark

Status: completed

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

- [x] Add CUDA candidate-core benchmark source.
- [x] Add build script.
- [x] Add ABI/benchmark contract doc.
- [x] Build benchmark on DGX with `nvcc`.
- [x] Run benchmark on DGX.
- [x] Verify matched counts.
- [x] Verify CUDA speedup over CPU.
- [x] Record compact proof and close this card.

## Merge Note

Implemented in repo commit `e4274ffe947c801eb2de22f8290c75eb914989a9` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

Benchmark dimensions:

- Query keys: 8,192
- Index keys: 32,768
- Pair count: 268,435,456
- Key space: 4,096
- Trials: 5 measured, 1 warmup
- CUDA launch: 65,535 blocks, 256 threads per block

Correctness gate passed: CPU and CUDA both counted 65,536 matches.

Performance gate passed:

- CPU best: 68.864532 ms
- CUDA kernel best: 1.249088 ms
- CUDA total best: 1.272772 ms
- CPU vs CUDA kernel speedup: 55.131848x
- CPU vs CUDA total speedup: 54.105945x

Proof paths:

- Build manifest: `out/m1j/e4274ff/build_manifest.json`
- Benchmark JSON: `out/m1j/e4274ff/cuda-candidate-core-bench.json`
- Compact golden proof: `tests/golden/cuda-candidate-core-bench-dgx-aarch64.json`

Scope caveat: this is a candidate equality-scan core benchmark, not a full Flye
speed claim. It excludes candidate TSV serialization, full `VertexIndex`
construction, CPU chaining, repeat graph construction, and polishing.
